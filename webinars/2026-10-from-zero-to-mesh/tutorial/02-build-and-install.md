# Step 2 of 9: Build the app and install the zones

You build the demo app image, then install Kong Mesh on each cluster. Each cluster becomes a zone that joins Konnect.

## Before you start

- Step 1 is done and your `.env` is loaded.
- `ZONE_TOKEN` and `OPERATOR_TOKEN` are set in this terminal.

## Do this

1. Build the demo app image from the `demo-app/` folder. The Dockerfile has no default base image. Give it a Python slim image pinned by digest. Read the digest first:

   ```
   docker buildx imagetools inspect python:3.13.5-slim --format '{{.Manifest.Digest}}'
   ```

   The commands below use Docker. Any build tool works.

   ```
   docker build --build-arg BASE=python:3.13.5-slim@sha256:<digest> -t <your registry>/demo-app:1 demo-app/
   ```

2. Push it.

   ```
   docker push <your registry>/demo-app:1
   ```

3. Set `DEMO_IMAGE` to the pushed path with its digest. It must end in `@sha256:` and 64 hex characters. A tag alone is refused.

   ```
   export DEMO_IMAGE=<your registry>/demo-app@sha256:<64 hex characters>
   ```

4. Install the zone on cluster 1. Replace the placeholders with your own values. `PEER_NAT_IPS` lists the other cluster's outbound addresses as /32 entries, separated by commas.

   ```
   code/bin/use-ctx.sh ready 1
   code/bin/fill-from-env.sh zone
   PEER_NAT_IPS=<zone 2 NAT addresses> code/bin/install-zone.sh ready <zone 1 name>
   ```

5. Install the zone on cluster 2.

   ```
   code/bin/use-ctx.sh ready 2
   code/bin/fill-from-env.sh zone
   PEER_NAT_IPS=<zone 1 NAT addresses> code/bin/install-zone.sh ready <zone 2 name>
   ```

   With only one cluster, set `SINGLE_CLUSTER=true` and `ALLOWED_SOURCE_RANGES` to your own address as a /32 instead of `PEER_NAT_IPS`.

6. Install the Kong Operator on cluster 1 only. It builds the gateway in step 4.

   ```
   code/bin/use-ctx.sh ready 1
   OPERATOR_SECRET_NAMESPACE=kong code/bin/fill-from-env.sh operator
   code/bin/install-operator.sh ready
   ```

## You are done when

- Each script finishes without an error.
- Konnect lists both zones as Online. Refresh the page if they are not there yet.

## What just happened

Each zone is a Kong Mesh control plane installed with one Helm chart. It joins the global control plane in Konnect with the token and address you gave it. The zone ingress only accepts calls from the addresses you listed, and the script refuses to install if that limit is missing.

## If something fails

The script names what is wrong, such as a missing variable or an open source range. Fix it and run the same command again.

Next: [Step 3, deploy the demo app](03-deploy-the-app.md)
