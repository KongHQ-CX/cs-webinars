# Step 6 of 9: The failure and the retry fix

You make half the calls fail, then add one policy that hides most of the failures.

## Before you start

- Steps 1 to 5 are done.
- The port-forward from step 4 is running and `GATEWAY_URL` is set in this terminal.

## Do this

1. Turn on the planted failure. Half the calls to the demo app now answer 503, in both zones.

   ```
   code/bin/use-ctx.sh ready 1
   code/bin/apply-stage.sh 04
   ```

2. Optional. Count the failures before the policy. Out of 200 requests, more than 80 should answer 503.

   ```
   code/stages/05-meshretry/verify.sh before
   ```

3. Apply the retry policy. It tells the mesh to retry a call up to 3 more times when the answer is a 503.

   ```
   code/bin/apply-stage.sh 05
   ```

## You are done when

Each script finishes without an error, and each runs its own check.

- Step 1 sends 100 requests through the gateway. About half answer 503. The check passes between 25 and 75.
- Step 3 sends 200 requests. Fewer than 25 answer 503.

## What just happened

The failure switch lives in the demo app. The script set it to 50 percent on every demo pod. `MeshRetry` is a Kubernetes object, and one object changes the behavior of every call between services. The application did not change.

## If something fails

Read the last lines. They name the check that failed. A proxy takes a moment to pick up a policy change, and the script waits for it before it counts. Fix the problem and run the same command again.

Next: [Step 7, identity and default deny](07-identity-and-default-deny.md)
