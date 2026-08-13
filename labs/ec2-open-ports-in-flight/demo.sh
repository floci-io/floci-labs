#!/usr/bin/env bash
# EC2: open ports in-flight. End-to-end demo against a local Floci.
# Requires: aws CLI v2, docker, and Floci running on :4566 with the Docker socket mounted.
set -euo pipefail

export AWS_ENDPOINT_URL=${AWS_ENDPOINT_URL:-http://localhost:4566}
export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-test}
export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-test}
export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-1}

step() { printf '\n\033[1;35m== %s\033[0m\n' "$*"; }

# Floci pulls alpine/socat the first time a port is opened, which can take ~30s
# on a cold host. Poll for the sidecar instead of sleeping a fixed couple of
# seconds, otherwise step 5 races the image pull.
wait_for_fwd() {  # $1=port  $2=up|gone  $3=timeout secs
  local i n
  for i in $(seq 1 "${3:-90}"); do
    n=$(docker ps --filter "name=floci-ec2-fwd-$IID-$1" --format '{{.Names}}')
    [ "$2" = up   ] && [ -n "$n" ] && return 0
    [ "$2" = gone ] && [ -z "$n" ] && return 0
    sleep 1
  done
  echo "timed out waiting for the forward on $1 to be $2"; return 1
}

step "Health check"
curl -sf "$AWS_ENDPOINT_URL/_floci/health" >/dev/null || {
  echo "Floci is not reachable on $AWS_ENDPOINT_URL, see README.md"; exit 1; }
echo "ok"

step "1. Security group with NO ingress rules"
SG=$(aws ec2 create-security-group --group-name inflight-demo-$RANDOM \
      --description "open ports in-flight demo" --query GroupId --output text)
echo "created $SG"

step "2. Launch an instance serving HTTP on :8080 (busybox httpd via UserData)"
IID=$(aws ec2 run-instances --image-id ami-alpine --instance-type t3.micro \
  --security-group-ids "$SG" \
  --user-data '#!/bin/sh
set -e
mkdir -p /www
echo "hello from inside EC2 (well, a container)" > /www/index.html
# alpine ships busybox without the httpd applet, it lives in busybox-extras
apk add --no-cache busybox-extras
httpd -p 8080 -h /www' \
  --query 'Instances[0].InstanceId' --output text)
echo "launched $IID"
aws ec2 wait instance-running --instance-ids "$IID"
sleep 3   # let UserData start httpd

step "3. Nothing is reachable yet: no forward sidecars exist"
docker ps --filter "name=floci-ec2-fwd-$IID" --format '{{.Names}}  {{.Ports}}' | grep . \
  && { echo "unexpected sidecar found"; exit 1; } || echo "(none, as expected)"

step "4. Open port 8080 on the RUNNING instance"
aws ec2 authorize-security-group-ingress --group-id "$SG" \
  --protocol tcp --port 8080 --cidr 0.0.0.0/0
wait_for_fwd 8080 up   # reconcile runs off the API thread
docker ps --filter "name=floci-ec2-fwd-$IID-8080" --format '{{.Names}}  {{.Ports}}'

step "5. Reach the app through the forwarded host port"
HOST_PORT=$(docker ps --filter "name=floci-ec2-fwd-$IID-8080" --format '{{.Ports}}' \
  | sed -n 's/.*:\([0-9]*\)->8080.*/\1/p' | head -1)
echo "host port: $HOST_PORT"
curl -s "http://localhost:$HOST_PORT/"

step "6. Revoke the rule and the sidecar goes away"
aws ec2 revoke-security-group-ingress --group-id "$SG" \
  --protocol tcp --port 8080 --cidr 0.0.0.0/0
wait_for_fwd 8080 gone 30 && echo "(gone, as expected)"

step "7. Guardrail: an allow-all rule does NOT spawn 65k sidecars"
aws ec2 authorize-security-group-ingress --group-id "$SG" \
  --protocol tcp --port 0-65535 --cidr 0.0.0.0/0
sleep 2
COUNT=$(docker ps --filter "name=floci-ec2-fwd-$IID" --format '{{.Names}}' | wc -l | tr -d ' ')
echo "forward sidecars after allow-all rule: $COUNT (wide spans are skipped)"

step "Cleanup"
aws ec2 terminate-instances --instance-ids "$IID" >/dev/null
aws ec2 wait instance-terminated --instance-ids "$IID"
aws ec2 delete-security-group --group-id "$SG"
echo "done"
