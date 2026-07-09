#!/usr/bin/env bash
# Sets the environment variables verify.sh / values.yaml steps expect for
# Lab 4. Source this (not execute) so the exports land in your shell:
#   source set-env.sh
#
# LB_IP is auto-discovered from the kong-dp LoadBalancer Service when
# possible; other vars fall back to the same defaults used across this repo's
# scripts (see lab-03-rbac/verify.sh, 00-base/cleanup.sh) so labs work
# out-of-the-box, but can be overridden by exporting them before sourcing.
NAMESPACE="${NAMESPACE:-kong}"

: "${KONNECT_PAT:=<type your Konnect PAT>}"
: "${KONNECT_CONTROL_PLANE_ID:=<type your Konnect Control plane ID>}"
: "${KONNECT_REGION:=in}"
: "${GATEWAY_HOST:=api.kong-air.example.com}"

DISCOVERED_LB_IP=$(kubectl get svc -n "$NAMESPACE" -l app=kong-dp \
  -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
: "${LB_IP:=${DISCOVERED_LB_IP:-34.93.131.176}}"

export KONNECT_PAT KONNECT_CONTROL_PLANE_ID KONNECT_REGION GATEWAY_HOST LB_IP NAMESPACE

echo "==> Lab environment set:"
echo "    NAMESPACE=$NAMESPACE"
echo "    GATEWAY_HOST=$GATEWAY_HOST"
echo "    LB_IP=$LB_IP"
echo "    KONNECT_REGION=$KONNECT_REGION"
echo "    KONNECT_CONTROL_PLANE_ID=$KONNECT_CONTROL_PLANE_ID"
echo "    KONNECT_PAT=${KONNECT_PAT:0:12}... (hidden)"
