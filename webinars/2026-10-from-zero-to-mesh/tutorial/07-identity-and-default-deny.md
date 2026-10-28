# Step 7 of 9: Identity and default deny

You add a second caller that has an identity but no allow rule. The mesh refuses it.

## Before you start

- Steps 1 to 6 are done, and stage 00 from step 5 has run.
- The port-forward and `GATEWAY_URL` from step 4 are still in place.
- `DEMO_IMAGE` and `MESH_NAME` are set.

## Do this

1. Add the denied client.

   ```
   code/bin/use-ctx.sh ready 1
   code/bin/apply-stage.sh 06
   ```

## You are done when

`apply-stage.sh` finishes without an error. Its check proves four things.

- The client pod has a sidecar, and 10 requests from it to the demo app all get 403.
- The same client cannot reach the demo app's admin port.
- Every allow rule names one caller by its full identity. No rule allows everyone.
- The gateway still works. Its requests are not denied.

## What just happened

Every workload has an identity, and an identity turns on mTLS. With mTLS on, the mesh denies every call that no rule allows. The gateway has a rule that names its exact identity, so its calls work. The new client has an identity but no rule names it, so the mesh refuses it.

## If something fails

Read the last lines. They name the check that failed. Fix it and run the same command again.

Next: [Step 8, failover](08-failover.md)
