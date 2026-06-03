#!/usr/bin/env bash
# deploy-workload.sh — BONUS, real-mode only. Needs the Docker CLI.
#
# Why not `aws eks update-kubeconfig`? Against Floci it produces a BROKEN kubeconfig:
#   1. describe-cluster returns endpoint https://floci-eks-<name>:6443 — a Docker-network
#      DNS name that doesn't resolve from the host (Floci runs in a container, so it
#      reports the container-internal endpoint, not the published host port).
#   2. Floci extracts only the CA from k3s; it hands back NO client credentials, and k3s
#      can't validate the `aws eks get-token` bearer token update-kubeconfig configures.
#      Result: every API call comes back 401 Unauthorized.
#
# So we go to the source of truth instead: pull k3s's own admin kubeconfig out of the
# container (it has the admin client cert/key), and point it at the host port Floci
# published for the k3s API server (range 6500-6599). k3s is started with
# --tls-san=localhost, so TLS to 127.0.0.1/localhost validates.
set -euo pipefail

CLUSTER="${CLUSTER:-hello-cluster}"
CONTAINER="floci-eks-${CLUSTER}"
KCFG="${KUBECONFIG:-./kubeconfig-${CLUSTER}}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say() { printf '\n\033[1;33m== %s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m  ✓ %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m  ✗ %s\033[0m\n' "$*"; exit 1; }

command -v docker  >/dev/null || die "docker CLI not found (this bonus needs it)"
command -v kubectl >/dev/null || die "kubectl not found"

say "Locate the k3s container for cluster '$CLUSTER'"
docker inspect "$CONTAINER" >/dev/null 2>&1 || die "container '$CONTAINER' not found — run ./run.sh first (and ensure Floci is in real mode, mock=false)"
ok "found container $CONTAINER"

say "Find the host port Floci published for the k3s API (6500-6599)"
# docker port maps container 6443 -> host port; take the port off the last field.
HOSTPORT="$(docker port "$CONTAINER" 6443 2>/dev/null | head -n1 | sed -E 's/.*:([0-9]+)$/\1/')"
[ -n "${HOSTPORT:-}" ] || die "could not read published port for $CONTAINER:6443"
ok "k3s API published on host port $HOSTPORT"

say "Pull k3s's admin kubeconfig and point it at the host port"
mkdir -p "$(dirname "$KCFG")"
docker exec "$CONTAINER" cat /etc/rancher/k3s/k3s.yaml > "$KCFG"
# k3s writes server: https://127.0.0.1:6443 — repoint at the published host port.
sed -i -E "s#server: https://127.0.0.1:6443#server: https://127.0.0.1:${HOSTPORT}#" "$KCFG"
export KUBECONFIG="$KCFG"
ok "kubeconfig written to $KCFG (admin client cert included)"

say "Confirm kubectl can reach AND authenticate to the API"
kubectl --request-timeout=15s get --raw /readyz >/dev/null 2>&1 || die "API not reachable/authorized at https://127.0.0.1:${HOSTPORT}"
kubectl get nodes
ok "authenticated to the k3s cluster"

say "Deploy nginx (Deployment + ClusterIP Service)"
kubectl apply -f "$HERE/k8s/nginx.yaml"
kubectl rollout status deployment/hello-nginx --timeout=120s
ok "deployment rolled out"

say "Verify pods and Service"
kubectl get pods,svc -l app=hello-nginx

say "Reach the app from inside the cluster"
kubectl run curltest --image=curlimages/curl:8.10.1 --restart=Never --rm -i --quiet -- \
  curl -fsS --max-time 10 http://hello-nginx.default.svc.cluster.local \
  | grep -qi "welcome to nginx" \
  && ok "got the nginx welcome page through the Service"

printf '\n\033[1;32mBonus passed — a workload is serving traffic on the Floci-backed k3s node.\033[0m\n'
echo "kubeconfig left at: $KCFG   (export KUBECONFIG=$KCFG to keep using kubectl)"
