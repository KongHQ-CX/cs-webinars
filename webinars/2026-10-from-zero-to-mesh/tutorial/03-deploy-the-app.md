# Step 3 of 9: Deploy the demo app

You run the demo app in both zones. Each copy reports the name of its zone, so you can see who answered.

## Before you start

- Steps 1 and 2 are done.
- `DEMO_IMAGE`, `MESH_NAME` and the two zone names are ready.

## Do this

1. Deploy to cluster 1.

   ```
   code/bin/use-ctx.sh ready 1
   ZONE_NAME=<zone 1 name> code/bin/apply-stage.sh 02
   ```

2. Deploy to cluster 2.

   ```
   code/bin/use-ctx.sh ready 2
   ZONE_NAME=<zone 2 name> code/bin/apply-stage.sh 02
   ```

## You are done when

`apply-stage.sh` finishes without an error. It runs a check after each deploy.

- Every demo pod is ready.
- Every demo pod has its sidecar, the mesh's proxy.
- The failure switch reads 0 on every pod.

## What just happened

The script created a `demo` namespace, a ServiceAccount per workload, the demo app Deployments and their Services. The app answers each request with its zone name. It also has a switch that makes a share of requests fail. You use that switch in step 6.

## If something fails

Read the last lines. They name the check that failed. Fix it and run the same command again.

Next: [Step 4, add the gateway](04-add-the-gateway.md)
