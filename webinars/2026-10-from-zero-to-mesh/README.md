# Service mesh across two zones with Kong Mesh

This folder holds the code the webinar ran. You can rebuild the setup with your own Konnect account and your own Kubernetes clusters. Nothing here needs another repository.

You set every value yourself. Each value you must supply is written `__REPLACE_ME__` in the files and in this page. A script stops and names any variable that is unset, empty or still `__REPLACE_ME__`.

## What is in the download

| Folder | What it holds |
|---|---|
| `tutorial/` | Nine short steps, from an empty Konnect account to a working mesh. Start with `tutorial/01-set-up-konnect.md` |
| `code/` | Helm values, manifests, and the scripts that install and demonstrate each step. `code/README.md` lists every script |
| `demo-app/` | The small web service the demo calls: `src/server.py`, `src/adminctl.py` and a Dockerfile. You build and push its image in tutorial step 2 |
| `From-Zero-to-Mesh-Webinar.pdf` | The slide deck from the session. [Watch the recording](https://konghq.com/events/webinars/from-zero-to-mesh-secure-resilient-traffic-between-your-services-with-kong-mesh) |
| `.env.example` | Every variable the scripts read except tokens, with `__REPLACE_ME__` for each value you supply. Tokens you enter with `read -rs` |

## What you need

- A Konnect account and a personal access token for it.
- Two Kubernetes clusters. Name the kubectl contexts `ready-1` and `ready-2` (`kubectl config rename-context <old> ready-1`). Zone 1 gets the gateway.
- `kubectl`, `helm`, `jq`, `yq` (mikefarah, v4) and `python3` on your PATH.
- A container registry you can push to, for the demo app image.

One cluster is enough for the zone install and for stages 02, 03, 04 and 05. Stage 00 checks both `ready-1` and `ready-2`, stage 06 needs stage 00, and stage 07 needs two zones. So the identity, trust and failover beats need two clusters.

Versions used: Kong Mesh 2.14.6 (chart `kong-mesh/kong-mesh`), Kong Operator chart `kong-operator` 1.4.2.

## Follow the tutorial

Do the steps in order. Each file is short, has the exact commands, and says what you should see.

1. [Set up Konnect](tutorial/01-set-up-konnect.md)
2. [Build the app and install the zones](tutorial/02-build-and-install.md)
3. [Deploy the demo app](tutorial/03-deploy-the-app.md)
4. [Add the gateway](tutorial/04-add-the-gateway.md)
5. [Identity and trust](tutorial/05-identity-and-trust.md)
6. [The failure and the retry fix](tutorial/06-failure-and-retry.md)
7. [Identity and default deny](tutorial/07-identity-and-default-deny.md)
8. [Failover](tutorial/08-failover.md)
9. [Reset and clean up](tutorial/09-reset-and-clean-up.md)

## Variables each stage needs

Every stage script checks its variables first and names any that are missing. The formats:

| Stage | Variable | Format |
|---|---|---|
| 02 app | `DEMO_IMAGE` | `<registry path>@sha256:<64 hex characters>`. A tag alone is refused |
| 02 app | `ZONE_NAME` | The zone name this cluster reports. Lowercase letters, digits and hyphens. Different on each cluster |
| 02 app | `MESH_NAME` | Lowercase letters, digits and hyphens |
| 03 gateway | `MESH_NAME`, `GATEWAY_CP_ID` | As above. `GATEWAY_CP_ID` is a UUID |
| 03 gateway | `KONNECT_SERVER_URL` | `<geo>.api.konghq.com` with geo `us`, `eu`, `au`, `me` or `in` |
| 03 gateway | `GATEWAY_IMAGE` | `<name>:<tag>@sha256:<64 hex characters>` with the tag pinned to a patch version |
| 03 gateway | `EDGE_CONTROL_ACK` (optional) | `1` says a firewall that admits only your own address is already in place on the load balancer. Without it the gateway Service is a ClusterIP and nothing is exposed outside the cluster. Reach it with a port-forward and set `GATEWAY_URL` for `verify.sh` |
| 03 gateway | others | Read the header of `code/stages/03-gateway/apply.sh` for the complete list, because it can change |
| 00 setup | `MESH_NAME`, `GATEWAY_SPIFFE_ID` | `GATEWAY_SPIFFE_ID` is `spiffe://<trust domain>/ns/kong/sa/<ServiceAccount>`. The default ServiceAccount is refused |
| 05 MeshRetry | `MESH_NAME` | As above |
| 06 identity | `DEMO_IMAGE`, `MESH_NAME` | As above |
| 07 failover | `LOCAL_ZONE`, `REMOTE_ZONE` | The zone names that `ready-1` and `ready-2` report. They must differ. `LOCAL_ZONE` defaults to `ZONE_NAME` |

## Safety notes

- No script prints a token. `fill-from-env.sh` sends the value to `kubectl` on standard input only.
- Stage 03 keeps the gateway closed (ClusterIP) until you set `EDGE_CONTROL_ACK=1`, which says the firewall is in place. The firewall rule on the load balancer is the only control on who can reach the gateway.
- To remove a zone, delete it in Konnect before you delete the cluster.
