#!/usr/bin/env bash
# teardown.sh — delete the workload and the EKS cluster from Floci.
set -euo pipefail

CLUSTER="${CLUSTER:-hello-cluster}"
export AWS_ENDPOINT_URL="${AWS_ENDPOINT_URL:-http://localhost:4566}"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Best-effort: if the API server isn't reachable from here, deleting the whole
# cluster below removes the workload anyway, so don't block on this.
kubectl delete -f "$HERE/k8s/nginx.yaml" --ignore-not-found --request-timeout=10s 2>/dev/null || \
  echo "(skipped kubectl delete — API not reachable; the cluster delete below covers it)"
aws eks delete-cluster --name "$CLUSTER" >/dev/null 2>&1 && echo "deleted cluster $CLUSTER" || echo "no cluster $CLUSTER to delete"
rm -f "$HERE/kubeconfig-$CLUSTER" 2>/dev/null && echo "removed kubeconfig-$CLUSTER" || true
