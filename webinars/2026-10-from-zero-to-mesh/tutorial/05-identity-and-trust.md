# Step 5 of 9: Identity and trust

Every workload in the mesh already has an identity. You now make the zones trust each other and let the gateway in.

## Before you start

- Steps 1 to 4 are done, so the gateway pod exists.
- `MESH_NAME` is set.

## Do this

1. Read two values on cluster 1.

   ```
   code/bin/use-ctx.sh ready 1
   kubectl get meshidentity -n kong-mesh-system -o jsonpath='{.items[0].spec.spiffeID.trustDomain}{"\n"}'
   kubectl get pods -n kong -o jsonpath='{.items[*].spec.serviceAccountName}{"\n"}'
   ```

   The first line is a template, `{{ .Mesh }}.{{ .Zone }}.mesh.local`. Replace `{{ .Mesh }}` with your `MESH_NAME` and `{{ .Zone }}` with zone 1's name. The second line is the gateway pod's ServiceAccount.

2. Build the gateway's identity from those two parts and export it.

   ```
   export GATEWAY_SPIFFE_ID=spiffe://<trust domain>/ns/kong/sa/<ServiceAccount>
   ```

   The Kong docs give no single command that reads this id, so you compose it. The script refuses `sa/default`.

3. Run the setup. It works on both clusters in one go.

   ```
   code/stages/00-setup/apply.sh
   ```

4. Check it.

   ```
   code/stages/00-setup/verify.sh
   ```

## You are done when

`verify.sh` finishes without an error.

- Both zones trust each other's certificate authority.
- One allow rule exists, and it names the gateway by its exact identity.
- Every demo and gateway pod started after the identity.

## What just happened

Each zone makes its own certificate authority, so calls across zones fail until every zone trusts the others. The script copied each authority to the other zone. It then added the one rule that lets the gateway call the demo app, and restarted the pods that started before the identity existed.

## If something fails

Read the last lines. They name the check that failed. Fix it and run the same command again.

Next: [Step 6, the failure and the retry fix](06-failure-and-retry.md)
