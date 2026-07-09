# Kong Security Labs — Hybrid Mode on GKE

Kong Gateway in **Konnect hybrid mode** (CP in Konnect cloud, DP on GKE via the **`kong/kong` Helm chart**).  
The Control Plane is created once in the Konnect UI, the DP client mTLS certificate is generated and
registered manually, and the DataPlane is installed as a plain Helm release (see

Backend: **Kong-Air** mock API — `/flights` and `/bookings` endpoints.  
Routing: **Services + Routes** created directly via the Konnect Admin API.

## Prerequisites

| Tool | Version |
|------|---------|
| `gcloud` CLI | Latest |
| `kubectl` | ≥ 1.28 |
| `helm` | ≥ 3.14 |
| `openssl` | Any |
| `python3` | ≥ 3.9 |
| Konnect account | Plus or Enterprise |

## Architecture

```
Konnect Cloud (Control Plane)
       │  cluster mTLS (self-managed cert) + config push
       │  Services / Routes created via Admin API
       ▼
GKE Cluster — kong namespace
  ├── kong-dp Helm release (DataPlane — LoadBalancer on :443, installed via kong/kong chart)
  │       │  routes traffic based on Route path rules
  │       ▼
  └── kong-air namespace
        └── kong-air    (Deployment — /flights + /bookings)
```

- **DataPlane workload** — a plain `kong/kong` Helm release. Every `env.*` value in a lab's `values.yaml`
  is passed straight through to a `KONG_*` container env var, with nothing rewritten underneath.
- **Control Plane** — created once, manually, in the Konnect UI (Gateway Manager → New Control Plane → Hybrid).
- **DP client mTLS certificate** — generated once (`openssl req -x509 ...`) and registered against the
  Control Plane manually (Konnect UI → Control Plane → Generate certificate), then loaded into a
  Kubernetes Secret via `00-base/02-create-cluster-cert-secret.sh`. No controller rotates or manages it.
- **Routing (Services/Routes)** — created directly via the Konnect Admin API
  (`00-base/06-kong-services-routes.sh`), the same `core-entities` endpoints the Konnect UI itself calls.

## Routing model

```
Route (flights-route)  ─► Service (flights-service,  path=/flights)  ─┐
                                                                        ├─► kong-air.kong-air.svc:80
Route (bookings-route) ─► Service (bookings-service, path=/bookings) ─┘
```
strip_path=true strips the prefix from the incoming URL; the service path re-adds it
so the upstream always receives the full path (`/flights/...`, `/bookings/...`).

Services and Routes are created directly in Konnect via the Admin API — there is no Kubernetes
object, controller, GatewayClass, Gateway, or HTTPRoute involved in routing at all.

## Quick Start

```bash
# 1. Provision GKE cluster
bash 00-base/00-gke-cluster.sh

# 2. Install prerequisites (cert-manager)
bash 00-base/01-install-prerequisites.sh

# 3. Create a Control Plane manually in the Konnect UI:
#    Gateway Manager → New Control Plane → Hybrid → name it "kong-labs-cp".
#    Note the Control Plane UUID (KONNECT_CONTROL_PLANE_ID) and, from its
#    Connectivity tab, the cluster_control_plane / cluster_telemetry_endpoint
#    hostnames — fill these into 00-base/helm/values.yaml (and each lab's
#    values.yaml).

# 4. Generate a DP client certificate and register it with that Control Plane:
#    Konnect UI → Control Plane → Generate certificate (or run
#    `openssl req -new -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1
#     -keyout cert/tls.key -out cert/tls.cert -days 3650 -subj "/CN=kong-dp"`
#    and upload cert/tls.cert as a "manual" DP certificate in the UI).
#    Then load it into a Secret:
bash 00-base/02-create-cluster-cert-secret.sh

# 5. Install HashiCorp Vault (HTTPS listener) and seed Kong-Air secrets —
#    used by Lab 2, installed here so Lab 2 doesn't pay the install cost
bash 00-base/03-install-vault.sh
bash 00-base/04-vault-init.sh

# 6. Install the DataPlane via Helm (HTTP-only — Secret 'kong-cluster-cert'
#    must exist first). TLS/HTTPS termination is introduced in Lab 1.
bash 00-base/06-install-dataplane.sh

# 7. Deploy Kong-Air backend
kubectl apply -f 00-base/backend/kong-air.yaml

# 8. Create Services + Routes directly in Konnect via the Admin API
export KONNECT_PAT="<personal-access-token>"
export KONNECT_CONTROL_PLANE_ID="<uuid-from-step-3>"
bash 00-base/07-kong-services-routes.sh

# 9. Verify
bash 00-base/verify.sh
```

## Cleanup

`cleanup.sh` tears down every resource created above and by the labs: the
`flights`/`bookings` Services + Routes, the Lab 5 rate-limiting plugin, the
Lab 3 RBAC team + invited user, and the `kong-dp` Helm release.

```bash
export KONNECT_PAT="<personal-access-token>"
export KONNECT_CONTROL_PLANE_ID="<uuid-from-step-3>"
bash cleanup.sh
```

It does not tear down the GKE cluster, Vault install, or Kong-Air backend —
re-run the relevant `00-base` step if you need those removed too.

## Labs

| Lab | Folder | Controls | Focus |
|-----|--------|----------|-------|
| Base | `00-base/` | — | GKE cluster, Helm DataPlane, kong-air backend |
| **Lab 1** | `lab-01-tls/` | #1 #15 | HTTPS-only, TLS 1.2+, CP→DP mTLS |
| **Lab 2** | `lab-02-vault/` | #2 #3 #8 | Zero plaintext credentials via HashiCorp Vault |
| **Lab 3** | `lab-03-rbac/` | #7 | Konnect Teams RBAC, scoped Viewer role |
| **Lab 4** | `lab-04-fingerprints/` | #12 #13 #16 #17 | Strip headers, disable access log, real IP |
| **Lab 5** | `lab-05-rate-limiting/` | #24 #19 #4 #5 | Rate limiting, audit logs, DP health |

Labs are **cumulative** — each `values.yaml` carries forward settings from prior labs.

## Key environment variables

```bash
export KONNECT_PAT="<personal-access-token>"
export KONNECT_CONTROL_PLANE_ID="<uuid-from-konnect-ui>"
export LB_IP="$(kubectl get svc -n kong -l app=kong-dp -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].status.loadBalancer.ingress[0].ip}')"
export GATEWAY_HOST="api.kong-air.example.com"
```

## File structure

```
kong-labs/
├── README.md
├── 00-base/
│   ├── 00-gke-cluster.sh
│   ├── 01-install-prerequisites.sh
│   ├── 02-create-cluster-cert-secret.sh ← loads cert/tls.cert+key into Secret 'kong-cluster-cert'
│   ├── 03-install-vault.sh              ← HashiCorp Vault, HTTPS listener (used by Lab 2)
│   ├── 04-vault-init.sh                 ← seeds Kong-Air secrets, creates AppRole + Secret
│   ├── 06-install-dataplane.sh          ← helm upgrade --install using helm/values.yaml
│   ├── 07-kong-services-routes.sh       ← Services + Routes via Konnect Admin API
│   ├── cert/
│   │   ├── tls.cert                     ← DP client cert (registered with Konnect manually)
│   │   └── tls.key
│   ├── vault/
│   │   └── vault-tls-certificate.yaml ← cert-manager Certificate for Vault's listener
│   ├── helm/
│   │   └── values.yaml               ← Base DataPlane Helm values (HTTP-only)
│   ├── tls/
│   │   ├── self-signed-issuer.yaml   ← cert-manager CA + ClusterIssuer (lab only)
│   │   └── proxy-certificate.yaml    ← leaf cert → Secret 'kong-proxy-tls'
│   ├── backend/
│   │   └── kong-air.yaml             ← Namespace + ConfigMap + Deployment + Service
│   └── verify.sh
├── lab-01-tls/
│   ├── README.md
│   ├── values.yaml
│   └── verify.sh
├── lab-02-vault/
│   ├── README.md
│   ├── 01-register-vault-konnect.sh  ← registers Vault backend with Konnect (Vault already running)
│   ├── values.yaml
│   └── verify.sh
├── lab-03-rbac/
│   ├── README.md
│   ├── 01-create-team.sh
│   ├── 02-assign-roles.sh
│   └── verify.sh
├── lab-04-fingerprints/
│   ├── README.md
│   ├── values.yaml
│   ├── request-transformer-plugin.sh
│   └── verify.sh
└── lab-05-rate-limiting/
    ├── README.md
    ├── redis.yaml
    ├── rate-limiting-plugin.sh
    ├── audit-log-webhook.sh
    ├── burst-test.sh
    └── verify.sh
```

Each lab's `values.yaml` is applied with:

```bash
helm upgrade --install kong-dp kong/kong -n kong -f values.yaml --wait
```
