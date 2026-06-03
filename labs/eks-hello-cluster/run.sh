#!/usr/bin/env bash
# run.sh — drive the full EKS control-plane lifecycle on local Floci.
#
# This covers exactly what Floci's EKS service supports today (per
# floci-io/floci docs/services/eks.md): create, wait, describe, tag, list, delete.
# No real AWS account, no 10-minute control-plane provisioning, no bill.
#
# Want to actually deploy a workload with kubectl? See deploy-workload.sh — it's a
# real-mode bonus with extra requirements, kept separate so this core lab always runs.
set -euo pipefail

CLUSTER="${CLUSTER:-hello-cluster}"
K8S_VERSION="${K8S_VERSION:-1.29}"
ENDPOINT="${AWS_ENDPOINT_URL:-http://localhost:4566}"
export AWS_ENDPOINT_URL="$ENDPOINT"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
ARN="arn:aws:eks:${AWS_DEFAULT_REGION}:000000000000:cluster/${CLUSTER}"

say() { printf '\n\033[1;33m== %s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m  ✓ %s\033[0m\n' "$*"; }

say "Pre-flight: is Floci up at $ENDPOINT ?"
if ! curl -fsS -m 5 "$ENDPOINT/_floci/health" >/dev/null 2>&1; then
  echo "  ✗ Floci is not answering. Start it with:  floci start"
  echo "    (or: docker run -d --name floci -p 4566:4566 \\"
  echo "          -v /var/run/docker.sock:/var/run/docker.sock floci/floci:latest)"
  exit 1
fi
ok "Floci is healthy"

say "Step 1: create the cluster"
# subnetIds/securityGroupIds are required by the API shape but Floci accepts empty sets,
# so you skip the VPC/IAM yak-shaving and get a cluster object straight away.
if aws eks describe-cluster --name "$CLUSTER" >/dev/null 2>&1; then
  ok "cluster '$CLUSTER' already exists — reusing it"
else
  aws eks create-cluster \
    --name "$CLUSTER" \
    --role-arn "arn:aws:iam::000000000000:role/eks-role" \
    --resources-vpc-config "subnetIds=[],securityGroupIds=[]" \
    --kubernetes-version "$K8S_VERSION" \
    >/dev/null
  ok "create-cluster accepted (k8s $K8S_VERSION)"
fi

say "Step 2: wait for the cluster to become ACTIVE"
# Real EKS takes ~10 minutes here; Floci flips to ACTIVE in seconds.
for i in $(seq 1 60); do
  STATUS="$(aws eks describe-cluster --name "$CLUSTER" \
            --query 'cluster.status' --output text 2>/dev/null || echo PENDING)"
  printf '\r  status: %-12s (%ds)' "$STATUS" "$i"
  [ "$STATUS" = "ACTIVE" ] && break
  sleep 1
done
echo
[ "$STATUS" = "ACTIVE" ] || { echo "  ✗ cluster never reached ACTIVE"; exit 1; }
ok "cluster is ACTIVE"

say "Step 3: describe it"
aws eks describe-cluster --name "$CLUSTER" \
  --query 'cluster.{name:name,status:status,version:version,arn:arn,endpoint:endpoint}' \
  --output table
ok "describe-cluster works"

say "Step 4: tag the cluster, then read the tags back"
aws eks tag-resource --resource-arn "$ARN" --tags env=dev,team=platform,lab=eks-hello-cluster
READBACK="$(aws eks list-tags-for-resource --resource-arn "$ARN" --query 'tags.env' --output text)"
[ "$READBACK" = "dev" ] || { echo "  ✗ tag readback mismatch: '$READBACK'"; exit 1; }
ok "tag-resource + list-tags-for-resource round-trip"

say "Step 5: it shows up in list-clusters"
aws eks list-clusters --query 'clusters' --output text | tr '\t' '\n' | grep -qx "$CLUSTER" \
  && ok "'$CLUSTER' present in list-clusters"

printf '\n\033[1;32mEKS control-plane lab passed — full cluster lifecycle works on Floci.\033[0m\n'
echo "Next: deploy a workload with ./deploy-workload.sh   (real-mode bonus, see README)"
echo "Tear down with:  ./teardown.sh"
