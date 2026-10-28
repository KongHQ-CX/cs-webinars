# Step 1 of 9: Set up Konnect

You create seven things in Konnect and write down the values. Nothing runs on your clusters yet.

## Before you start

- A Konnect account and a personal access token for it.
- Two Kubernetes clusters. Name the kubectl contexts `ready-1` and `ready-2`: `kubectl config rename-context <old> ready-1`.
- `kubectl`, `helm`, `jq`, `yq` (mikefarah, v4) and `python3` on your PATH.
- A container registry you can push to.

## Do this

1. Create the **mesh control plane**. Konnect hosts it, and it is the global control plane. Write down its id. It is your `KONNECT_CP_ID`.
   Guide: https://developer.konghq.com/mesh/deploy-mesh-using-terraform-and-konnect/
2. Create the **mesh** in that control plane with `meshServices` mode `Exclusive` (`mesh_services.mode.str = "Exclusive"` in the Terraform provider). Its name is your `MESH_NAME`.
   After a zone is up, run `kubectl get meshretries -A` and delete any default policy you find. The setting `skip_creating_initial_policies = ["*"]` may not skip every default policy.
3. Create the **MeshIdentity**. It gives each workload an identity, which turns on mTLS. With no allow rule, traffic is denied, and later steps rely on that. The file `../code/stages/06-identity-deny/shown/meshidentity.yaml` shows the object.
   Guide: https://developer.konghq.com/mesh/issue-identity-with-meshidentity/
4. Create a **system account** with the `Connector` role and a token for it. The token is your `ZONE_TOKEN`. The same page shows the sync address, which looks like `grpcs://<region>.mesh.sync.konghq.com:443`. It is your `KDS_GLOBAL_ADDRESS`.
   Guide: https://developer.konghq.com/mesh/configure-mesh-global-control-plane-on-kubernetes-with-konnect-api/
5. Create the **gateway control plane**. Write down its id, a UUID. It is your `GATEWAY_CP_ID`.
   Guide: https://developer.konghq.com/operator/get-started/gateway-api/deploy-gateway/
6. Create a **second system account** and a second token for the Kong Operator. It is your `OPERATOR_TOKEN`. No Kong page we checked names the role this token needs, so start from the authentication page and expect to adjust the role.
   Guide: https://developer.konghq.com/operator/get-started/konnect-crds/authentication/
7. Create the **MeshMultiZoneService** named `demo-app` on the mesh control plane. It puts the demo app of every zone behind one name. The file `../code/stages/07-multizone-failover/shown/meshmultizoneservice.yaml` shows the fields. Use the Terraform provider or the Konnect Mesh API, then check the object exists before step 8.
   Guide: https://developer.konghq.com/mesh/meshmultizoneservice/

## Save your values

1. In this folder, copy the example file.

   ```
   cp .env.example .env
   ```

2. Open `.env` and replace each `__REPLACE_ME__` with your value. Leave the lines you do not have yet.
3. Load it in the terminal you will use for every step.

   ```
   set -a; . ./.env; set +a
   ```

4. Enter your two tokens. Type them in your terminal, not in a file.

   ```
   read -rs ZONE_TOKEN; export ZONE_TOKEN
   read -rs OPERATOR_TOKEN; export OPERATOR_TOKEN
   ```

## You are done when

- You have `KONNECT_CP_ID`, `MESH_NAME`, `KDS_GLOBAL_ADDRESS`, `GATEWAY_CP_ID`, `ZONE_TOKEN` and `OPERATOR_TOKEN`.
- Konnect shows the mesh and the `MeshMultiZoneService`.

## If something fails

Every script stops and names the variable that is unset, empty or still `__REPLACE_ME__`. Set it and run the step again.

Next: [Step 2, build the app and install the zones](02-build-and-install.md)
