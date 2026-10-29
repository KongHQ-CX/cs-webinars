# Step 8 of 9: Failover

You remove the demo app from zone 1. The answers keep coming, now from zone 2.

## Before you start

- Steps 1 to 7 are done.
- The `MeshMultiZoneService` named `demo-app` exists (step 1, item 7).
- The port-forward and `GATEWAY_URL` from step 4 are still in place.
- Set both zone names.

  ```
  export LOCAL_ZONE=<the zone name cluster 1 reports>
  export REMOTE_ZONE=<the zone name cluster 2 reports>
  ```

## Do this

1. Point the gateway at the `MeshMultiZoneService`. This also sets the failure switch back to 0 in both zones.

   ```
   code/bin/use-ctx.sh ready 1
   code/bin/apply-stage.sh 07
   ```

   This change rolls the gateway pods, which ends the port-forward from step 4 (`error: lost
   connection to pod`). Start it again in the second terminal, with the same command, as soon
   as the new gateway pod is Ready. `30-revert-gateway-path.sh` in item 4 rolls the pods again,
   so start it again after that too.

   Wait for the line `gateway warm after Ns` before you go on. The gateway needs a short time to settle after this change.

2. Remove the demo app from zone 1.

   ```
   code/stages/07-multizone-failover/10-kill-local.sh
   code/stages/07-multizone-failover/verify.sh killed
   ```

3. Bring it back.

   ```
   code/stages/07-multizone-failover/20-restore-local.sh
   code/stages/07-multizone-failover/verify.sh restored
   ```

4. Put the gateway path back as it was before this step.

   ```
   code/stages/07-multizone-failover/30-revert-gateway-path.sh
   ```

## You are done when

- After step 2, 100 requests through the gateway all answer 200, and none comes from zone 1.
- After step 3, 100 requests all answer 200 again, and they come from zone 1.

## What just happened

Until now the gateway sent calls to the demo app in its own zone. Now it sends them to one name that stands for the demo app in every zone, and the mesh picks the instance. When zone 1 has no pod left, the mesh sends the calls to zone 2. Nothing in the application or the gateway changed to make that happen.

## If something fails

Read the last lines. They name the check that failed. The `killed` check waits up to 90 seconds for the mesh to stop sending calls to the empty zone. Fix the problem and run the same command again.

Next: [Step 9, reset and clean up](09-reset-and-clean-up.md)
