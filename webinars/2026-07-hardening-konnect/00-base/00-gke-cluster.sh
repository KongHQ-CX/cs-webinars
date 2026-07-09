#!/usr/bin/env bash
# Creates a GKE cluster sized for the Kong labs.
set -euo pipefail

PROJECT="${GCP_PROJECT:-gcp-csm-support}"
REGION="${GCP_REGION:-asia-south1}"
CLUSTER="${CLUSTER_NAME:-kong-lab}"
NODE_COUNT="${NODE_COUNT:-2}"
MACHINE="${MACHINE_TYPE:-e2-standard-2}"

echo "==> Creating GKE cluster: $CLUSTER in $REGION"

gcloud container clusters create "$CLUSTER" \
  --project="$PROJECT" \
  --region="$REGION" \
  --num-nodes="$NODE_COUNT" \
  --machine-type="$MACHINE" \
  --workload-pool="${PROJECT}.svc.id.goog" \
  --enable-ip-alias \
  --release-channel=stable \
  --addons=HttpLoadBalancing,GcePersistentDiskCsiDriver

echo "==> Fetching credentials"
gcloud container clusters get-credentials "$CLUSTER" \
  --region="$REGION" \
  --project="$PROJECT"

kubectl cluster-info
