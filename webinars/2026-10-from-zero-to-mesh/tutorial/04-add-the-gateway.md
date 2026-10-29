# Step 4 of 9: Add the gateway

You add one gateway in front of the demo app, on cluster 1 only. The Kong Operator builds it from Kubernetes objects.

## Before you start

- Steps 1 to 3 are done.
- `MESH_NAME`, `GATEWAY_CP_ID`, `KONNECT_SERVER_URL` and `GATEWAY_IMAGE` are set. `KONNECT_SERVER_URL` is `<geo>.api.konghq.com` with geo `us`, `eu`, `au`, `me` or `in`. `GATEWAY_IMAGE` is `<name>:<tag>@sha256:<64 hex characters>`, with the tag pinned to a patch version.

## Do this

1. Apply the gateway to cluster 1.

   ```
   code/bin/use-ctx.sh ready 1
   code/bin/apply-stage.sh 03
   ```

   Before it creates anything, the script checks every manifest offline. A typo cannot leave half a gateway.

2. The gateway has no outside address yet, so the check at the end of the script may stop with a message about `GATEWAY_URL`. That is expected. Find the gateway's ingress Service.

   ```
   kubectl get svc -n kong
   ```

3. Open a second terminal and forward a local port to that Service. Leave it running.

   ```
   kubectl port-forward -n kong svc/<the ingress Service name> 8080:80
   ```

   The gateway answers HTTP on port 80. If `kubectl get svc` shows another port for HTTP, use that one.

4. In your first terminal, tell the scripts where the gateway is, then run the check.

   ```
   export GATEWAY_URL=http://localhost:8080
   code/stages/03-gateway/verify.sh
   ```

   Keep `GATEWAY_URL` set and the port-forward running for steps 5 to 8.

## You are done when

`verify.sh` finishes without an error.

- The Gateway is `Programmed`.
- The gateway pods have their sidecar.
- `GET /` through the gateway returns 200, or 403 `RBAC: access denied` while no
  `MeshTrafficPermission` exists yet. `verify.sh` says so and passes. Step 5 adds the allow
  rule, and the same check then reads 200.
- Nothing under `/admin` is routed.

## What just happened

The gateway is the front door. The mesh puts a sidecar next to it for its calls into the mesh. The only route is `GET /`. The gateway Service stays inside the cluster, so nothing is open to the internet.

## Want a public address instead?

Create a firewall rule on the gateway's load balancer that admits only your own address. Then set `EDGE_CONTROL_ACK=1` and run `code/bin/apply-stage.sh 03` again. The flag is only your statement that the firewall exists, and no script checks it. The firewall rule is the only control on who can reach the gateway.

For HTTPS, see "Optional: HTTPS for the gateway" in [code/README.md](../code/README.md).

## If something fails

Read the last lines. They name the check that failed. Fix it and run the same command again.

Next: [Step 5, identity and trust](05-identity-and-trust.md)
