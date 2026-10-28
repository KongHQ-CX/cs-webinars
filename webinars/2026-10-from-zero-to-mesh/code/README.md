# code/

Manifests, Kong Operator and gateway config, mesh policies, helper scripts. Every file cites the Kong docs page it comes from.

## Helper layer

All scripts read plain environment variables. Each one calls `require_vars` first, which names every variable that is unset, empty or still `__REPLACE_ME__`. No script prints a secret.

| File | What it does |
|---|---|
| `lib/common.sh` | `require_vars`, `require_ctx`, `require_ctx_1` (the one context guard for stages that talk to the gateway, follows `CTX_1`), `wait_pods`, `has_sidecar`, `require_single_cidr32`, `require_cidr32_list`, `require_ipv4_cidr`, `require_gateway_spiffe_id`, `fill_secret` |
| `lib/gateway.sh` | Gateway helpers for the stage checks: `gateway_url`, `request_once`, `count_requests`, `gateway_svc_local`, `gateway_no_world_policy`, `gateway_observed_generation` and `wait_gateway_rollout` (wait for a new observed generation, then the rollout) |
| `bin/use-ctx.sh <install\|ready> [1\|2]` | Switch the kubectl context (kubectx if installed) and write the prompt marker |
| `bin/apply-stage.sh <NN>` | Run `stages/NN-*/apply.sh`, or the first `10-*.sh` if there is none, then `verify.sh` |
| `bin/cleanup.sh [both]` | Return a ready cluster to the state before the baseline step. Safe to run twice. It restores the pods stage 07 killed and reverts the gateway path first, then resets the failure switch. A cluster with no demo pod at the switch step gives a warning, not a stop. `both` works on a private copy of the kubeconfig and leaves your current context alone |
| `bin/install-operator.sh <install\|ready>` | Install Kong Operator (chart `kong-operator` 1.4.2, Konnect controller on) on the zone 1 context from `helm/operator.values.yaml`. Renders the chart first and refuses to install without `ENABLE_CONTROLLER_KONNECT=true` and a full image version tag |
| `bin/install-cert-manager.sh` | Optional HTTPS. Install cert-manager (chart v1.21.2, `helm/cert-manager.values.yaml`) on the gateway cluster, then apply `tls/clusterissuer.yaml` and `tls/certificate.yaml` for a Let's Encrypt certificate by DNS-01 through the Cloudflare API. The result is the Secret `demo-gateway-tls` in namespace `kong`, labelled `konghq.com/secret: "true"`, which the HTTPS listener of the stage 03 `Gateway` reads. Needs `DNS_NAME`, `DNS_ZONE`, `TLS_EMAIL` and `CLOUDFLARE_API_TOKEN` in the environment of that one command. `TLS_STAGING=1` uses the Let's Encrypt staging server, `RENDER_ONLY=1` prints the manifests and changes nothing |
| `bin/dns.sh up\|down\|check` | Create, delete or check a DNS-only Cloudflare A record that points `DNS_NAME` at the gateway load balancer address. Needs `DNS_NAME`, `DNS_ZONE` and `CLOUDFLARE_API_TOKEN`. Keep it unproxied. Run `up` again after a cluster rebuild, because the address changes. `check` needs `dig` |
| `bin/fill-from-env.sh <zone\|operator>` | Fill a token Secret from `ZONE_TOKEN` or `OPERATOR_TOKEN` |
| `bin/install-zone.sh <install\|ready> <zone-name>` | Install a zone control plane and mesh-scoped zone proxies with Helm from `helm/install-zone.values.yaml`. Needs `KONNECT_CP_ID`, `KDS_GLOBAL_ADDRESS`, `MESH_NAME` and `PEER_NAT_IPS` (or `SINGLE_CLUSTER=true` with `ALLOWED_SOURCE_RANGES`) |
| `bin/trust-combine.sh` | Copy each zone's CA certificate into the other zones, one `MeshTrust` per source zone with its own trust domain. Needs `MESH_NAME` and `ZONE_CONTEXTS`. `COMBINED=1` applies one combined `MeshTrust` instead and needs one shared trust domain |
| `stages/00-setup/render-allow-rule.sh` | Print the gateway allow rule with `MESH_NAME` and `GATEWAY_SPIFFE_ID` filled in. Refuses an ID that is not `spiffe://<trust domain>/ns/kong/sa/<ServiceAccount>` and refuses `sa/default`. Pipe it to `kubectl apply` |
| `stages/00-setup/apply.sh` | Run once after stage 03 (the gateway ID is read from the gateway pod) and before stage 04, on `ready-1` and `ready-2`. Needs `MESH_NAME` and `GATEWAY_SPIFFE_ID`. In order: check both contexts exist, check a `MeshIdentity` exists on each cluster (see Identity below), run `bin/trust-combine.sh`, apply the gateway allow rule from `render-allow-rule.sh` with strict validation, delete any rule labelled `lab-allow`, then run `restart-workloads.sh` on each cluster. `COMBINED=1` goes through to the trust copy. `CTX_1` and `CTX_2` name the contexts |
| `stages/00-setup/restart-workloads.sh` | Restart the Deployments labelled `app=demo-app` and the gateway Deployments (label `gateway-operator.konghq.com/managed-by=dataplane`) on one context (`KUBECTL_CONTEXT`, else the active one) when a Running or Pending pod there is older than the newest `MeshIdentity` or `MeshTrust` of `MESH_NAME`. After the rollout it checks pod ages again, deletes pods that are still old by label, and fails if any remain. A second run restarts nothing. A selector with no Deployment is skipped |
| `stages/00-setup/verify.sh` | Check setup is present on `ready-1` and `ready-2`: `MeshIdentity`, the `MeshTrust` copies `bin/trust-combine.sh` applies (needs `MESH_NAME`, and `COMBINED=1` after a combined run), the allow rule, no `lab-allow` rule, no pod older than the identity |
| `stages/00-setup/verify-baseline.sh` | Check the state before the baseline step, after `cleanup.sh`. On `ready-1` it also checks that every gateway `LoadBalancer` Service has `externalTrafficPolicy: Local` and that no `NetworkPolicy` of ours admits the world |

## Stages

Each stage script starts with `Prerequisites:` and `Say:` comment lines. Run a stage with `bin/apply-stage.sh <NN>`. Every stage that talks to the gateway runs on `ready-1` (`CTX_1`).

| Stage | Scripts | Prerequisites | What to say |
|---|---|---|---|
| 02 app | `apply.sh`, `verify.sh`, `verify-switch.sh` | Zone control plane in the cluster. Run once per ready cluster with that cluster's `ZONE_NAME` | The demo app runs in both zones and reports its zone. One switch sets the failure rate in both |
| 03 gateway | `apply.sh`, `verify.sh`, `service-upstream.patch.yaml` (the `Gateway` has an HTTP listener and an HTTPS listener that reads `demo-gateway-tls`, see `bin/install-cert-manager.sh`) | `bin/install-operator.sh` ran, token Secret in namespace `kong`, `ready-1`, `python3` and `yq` on the machine. `apply.sh` needs `MESH_NAME`, `GATEWAY_CP_ID`, `KONNECT_SERVER_URL` (geo `us`, `eu`, `au`, `me` or `in`), `GATEWAY_IMAGE` (`name:tag@sha256:<64 hex>`). `EDGE_CONTROL_ACK=1` (optional) says the load balancer firewall is already in place: only then is the ingress Service a LoadBalancer, otherwise it is a ClusterIP and nothing is exposed | The gateway is the front door, and the only route is `GET /`. It is called restricted to your own address after the firewall port check passes and a request from a second address times out |
| 04 baseline failure | `10-failure-on.sh`, `20-failure-off.sh`, `verify.sh` | Stage 03 in place | About half the calls fail with a 503 |
| 05 MeshRetry | `apply.sh`, `verify.sh [before]` | Stages 03 and 04 in place. `MESH_NAME` | Retry up to 3 more times on a 503. The red rows thin out |
| 06 identity and the denied client | `apply.sh`, `verify.sh`, `20-denied-client.yaml`, `shown/meshidentity.yaml` | Stages 00, 02 and 03 in place, `ready-1`. `apply.sh` needs `DEMO_IMAGE` (`name:tag@sha256:<64 hex>`) and `MESH_NAME`. It checks a `MeshIdentity` exists and applies only the client pod, a second caller with its own ServiceAccount that no allow rule names. `shown/meshidentity.yaml` is the read-only copy to show, not applied here. `verify.sh` checks the client pod runs the sidecar, 10 requests from it all get 403 (a 200, 503 or no answer fails), the admin port refuses the connection, every `MeshTrafficPermission` is free of `spec.from` and every allow entry names one caller as `/ns/<name>/sa/<name>`, and the gateway still answers 200 | Every workload has an identity, which turns on mTLS and default deny. The gateway is allowed by its exact identity. A second client has an identity but no rule, so the mesh refuses it |
| 07 multizone failover | `apply.sh`, `10-kill-local.sh`, `20-restore-local.sh`, `30-revert-gateway-path.sh`, `verify.sh [killed\|restored]` | Stages 00 to 03, the `MeshMultiZoneService` on the global control plane. `verify.sh` needs `REMOTE_ZONE` and `LOCAL_ZONE` (default `ZONE_NAME`) | Remove the app from this zone and the answers keep coming from the other zone |

Stage 03 does not limit who can reach the gateway. The `GatewayConfiguration` has no source range field, and a `NetworkPolicy` cannot narrow the gateway: the Operator creates its own policy for the gateway pods with open proxy and metrics rules, policies add up, and the Operator reverts edits to its own. The limit is a firewall rule on the load balancer (allow your own address, deny the rest), set up outside this folder. `20-gatewayconfiguration.yaml` makes the ingress Service a ClusterIP unless `EDGE_CONTROL_ACK=1`, and then a LoadBalancer with `externalTrafficPolicy: Local` so the firewall sees the client address (lab check, not proven yet). `apply.sh` checks the stage 03 manifests before it creates the gateway: the offline schema checker (`lib/manifests_check.py --stage`, which prints its findings and rejects a misspelled or nonexistent `GatewayConfiguration` field; the other kinds are checked by the server-side dry run with `--validate=strict`). It reads the `GatewayConfiguration` back before it applies the `Gateway`. After the `Gateway` is Programmed it reads the live Service and the policies again. A trap deletes the `Gateway` when this run created it and stops early. On a rerun that finds a serving `Gateway`, only a read-back that proves the edge is wrong (configuration, live Service, a world-open policy) deletes it. Every `kubectl` call uses the context captured at the start. The route is applied last, only after those checks pass. `verify.sh` checks the same objects and that the `Gateway` is Programmed. It does not prove the firewall: test it from a second address, which should time out.

Policies applied on a zone carry `kuma.io/origin: zone`. The checker requires it outside `shown/`.

`cleanup.sh` keeps stage 00 and deletes the stage 06 client pod with the other stage files from 04 on.

### Identity

The setup checks that a `MeshIdentity` exists and never creates one. Create it once on the Konnect-hosted global control plane through the Konnect Mesh API, with a Konnect token in `KONNECT_TOKEN`:

```
curl -X PUT "https://$KONNECT_REGION.api.konghq.com/v1/mesh/control-planes/$CONTROL_PLANE_ID/api/meshes/$MESH_NAME/meshidentities/identity" \
  -H "Authorization: Bearer $KONNECT_TOKEN" -H "Content-Type: application/json" \
  --data '{"type":"MeshIdentity","name":"identity","spec":{"selector":{"dataplane":{"matchLabels":{}}},
    "spiffeID":{"trustDomain":"{{ .Mesh }}.{{ .Zone }}.mesh.local","path":"/ns/{{ .Namespace }}/sa/{{ .ServiceAccount }}"},
    "provider":{"type":"Bundled","bundled":{"meshTrustCreation":"Enabled","insecureAllowSelfSigned":true,
      "certificateParameters":{"expiry":"24h"},"autogenerate":{"enabled":true}}}}}'
```

`stages/06-identity-deny/shown/meshidentity.yaml` shows the same object as YAML. The Mesh must have `meshServices.mode: Exclusive`.

### Variables

| Name | Used for |
|---|---|
| `PEER_NAT_IPS` | Comma-separated /32 list for the zone ingress and egress source ranges |
| `SINGLE_CLUSTER` | Set to `true` with one cluster. Then `ALLOWED_SOURCE_RANGES` must hold your own /32 list |
| `ALLOWED_SOURCE_RANGES` | The /32 list used in place of `PEER_NAT_IPS` on a single cluster |
| `ZONE_TOKEN`, `OPERATOR_TOKEN` | Tokens for `fill-from-env.sh`. The Operator Secret goes in namespace `kong` by default (`OPERATOR_SECRET_NAMESPACE`) |
| `CTX_1`, `CTX_2` | Context names of the two zones (default `ready-1`, `ready-2`) |
| `GATEWAY_SPIFFE_ID` | `spiffe://<trust domain>/ns/kong/sa/<ServiceAccount>`, read from the gateway pod. Used by `render-allow-rule.sh` |
| `LOCAL_ZONE`, `REMOTE_ZONE` | Stage 07 `verify.sh`: the zone names of `ready-1` and `ready-2`. `LOCAL_ZONE` defaults to `ZONE_NAME` |

Anything you must supply is `__REPLACE_ME__` in the files. Replace it before you run a script. A script refuses the placeholder.

### Secrets

`fill_secret <ns> <name> <key> [label=value ...]` reads the value from stdin, refuses an empty value and the string `null`, creates the namespace, then creates the Secret from `/dev/stdin`. The value is never in a command line. It turns shell tracing off first, so `bash -x` does not print it. The optional labels go on the Secret. The Kong Operator reads only Secrets labelled `konghq.com/secret=true`, and a Konnect token Secret also needs `konghq.com/credential=konnect`. `fill-from-env.sh operator` sets both.

Enter a token without putting it on a command line or in your shell history:

```
read -rs ZONE_TOKEN; export ZONE_TOKEN
code/bin/fill-from-env.sh zone
```

For the Operator token, use `OPERATOR_TOKEN` and `fill-from-env.sh operator`.

### Prompt marker

`use-ctx.sh` writes the active context name to `~/.local/state/service-mesh-webinar/context` (override with `WEBINAR_STATE_DIR`). Show it in your prompt, for example `cat ~/.local/state/service-mesh-webinar/context`. A script cannot change the prompt of the shell that started it.

### Gateway warm-up

`wait_gateway_warm` (in `lib/gateway.sh`) is the gateway warm-up wait that stage 07 `verify.sh` (up mode only) runs before it counts requests: it waits for `WARM_CONSECUTIVE` (default 40) answers of 200 in a row, up to `WARM_TIMEOUT` seconds (default 90), and prints `gateway warm after Ns`. Wait for that line before running stage 07. Stage 07 `killed` and `restored` do not wait, because the failures there are the failover the stage shows. Stages 04 and 05 measure a deliberate failure share, stage 06 expects denials, and stage 03 has its own poll, so none of them waits.

### Manifest checker

Stage 03 `apply.sh` checks every manifest before it creates anything, so a typo cannot leave half a gateway. It runs `lib/manifests_check.py`, an offline check of the Gateway objects against the field list in `lib/crd-schemas.json` (a snapshot of the Kong Operator v2.3.3 schemas). It needs `python3` and `yq`.

## Optional: HTTPS for the gateway

The gateway has two listeners. The HTTP listener on port 80 is the default path, and every step in the main README works with it alone. The `Gateway` also has an HTTPS listener on port 443. It ends TLS at the gateway, and the route attaches to both listeners. Inside the mesh, the traffic is still mTLS between sidecars.

The HTTPS listener needs one thing: a TLS Secret named `demo-gateway-tls` in namespace `kong`, labelled `konghq.com/secret: "true"`. Kong Operator reads a certificate Secret only when it has that label. Without the label the listener reports `InvalidCertificateRef`, even though the Secret exists. The HTTP listener keeps answering while the Secret is missing. Create the Secret before you run stage 03.

`code/bin/install-cert-manager.sh` is one way to get it. It installs cert-manager with Helm, then applies a `ClusterIssuer` for Let's Encrypt and a `Certificate` that fills the Secret. It proves the name with a DNS-01 check through the Cloudflare API, so you need a name in a DNS zone you control at Cloudflare. Set these in the environment of that one command:

- `DNS_NAME`: the name for the certificate, such as `<your gateway name>`.
- `DNS_ZONE`: the Cloudflare zone that holds the name.
- `TLS_EMAIL`: where Let's Encrypt sends expiry notices.
- `CLOUDFLARE_API_TOKEN`: a token with Zone:Read and Zone:DNS:Edit on that one zone. The script sends it to `kubectl` on standard input and never prints it.

Set `TLS_STAGING=1` while you test, so a mistake does not use up production certificates. `code/bin/dns.sh up` creates the DNS-only record that points the name at the gateway load balancer address. Keep the record unproxied. The address changes when you rebuild the cluster, so run it again then. With another DNS provider, create the Secret yourself in the same shape, and skip both scripts.
