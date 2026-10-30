# Step 9 of 9: Reset and clean up

You put the clusters back to the state before the failure, so you can run steps 6 to 8 again.

## Do this

1. Reset one cluster.

   ```
   code/bin/use-ctx.sh ready 1
   code/bin/cleanup.sh
   ```

2. Or reset both clusters in one go.

   ```
   code/bin/cleanup.sh both
   ```

## What it does

- Sets the failure switch back to 0.
- Removes the retry policy and the denied client.
- Brings back any demo pods that step 8 removed, and reverts the gateway path.
- Keeps the identity setup from step 5, the app from step 3 and the gateway from step 4.

It is safe to run twice.

## Remove everything

- Delete a zone in Konnect before you delete its cluster, and disconnect it first. Konnect
  refuses a connected zone with 400 `zone "<name>" is still online. Disconnect the zone first`.
  Remove the zone control plane, then delete the zone:

  ```
  helm uninstall kong-mesh -n kong-mesh-system --wait
  curl -X DELETE "https://<geo>.api.konghq.com/v1/mesh/control-planes/<KONNECT_CP_ID>/api/zones/<zone name>" \
    -H "Authorization: Bearer $KONNECT_TOKEN"
  ```
- Delete the Konnect objects you created in step 1 when you are finished, and revoke both tokens.
  Konnect refuses to delete a mesh while data planes are still attached to it, so remove the
  zones and their data planes first. Deleting a mesh control plane also removes its zones and
  its mesh, so you can delete the control plane once every zone is offline.

## Where to go next

- [Optional HTTPS for the gateway](../code/README.md)
- [Every script and what it does](../code/README.md)
- The slides from the session are in `From-Zero-to-Mesh-Webinar.pdf`.
