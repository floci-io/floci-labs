# EKS Hello Cluster

> Drive the full EKS cluster lifecycle — create, wait for `ACTIVE`, describe, tag, list, delete — on local Floci, with no AWS account and none of the ~10-minute control-plane wait.

## What it shows

- The EKS control-plane API (`create-cluster`, `describe-cluster`, `tag-resource`, `list-clusters`, `delete-cluster`) running against Floci instead of real AWS
- A cluster going `ACTIVE` in seconds instead of ~10 minutes, so you can iterate on EKS automation / IaC without burning time or money
- That the only change from a real-AWS script is `AWS_ENDPOINT_URL`
- **Bonus (real mode):** deploying an actual nginx workload with `kubectl` against the k3s node Floci stands up

## Stack

- Language / runtime: Bash + AWS CLI v2 (`kubectl` only for the optional bonus)
- AWS services used: EKS
- Anything else worth knowing: see "What Floci's EKS supports" below — the supported surface is the control-plane API; the kubectl path is an undocumented real-mode extra

## Run it

Assumes Floci is running on `localhost:4566`. If not:

```bash
docker run -d --name floci -p 4566:4566 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  floci/floci:latest
```

(or just `floci start` if you have the CLI). Then:

```bash
chmod +x run.sh deploy-workload.sh teardown.sh
./run.sh            # the core lab — create, describe, tag, list
./deploy-workload.sh   # optional bonus — kubectl deploy (real mode; see caveats)
./teardown.sh
```

## What Floci's EKS supports

Per the [Floci EKS docs](https://github.com/floci-io/floci/blob/main/docs/services/eks.md), the supported operations are:

| Supported | Not supported (yet) |
|-----------|---------------------|
| `CreateCluster` | Node groups (`CreateNodegroup`, …) |
| `DescribeCluster` | Fargate profiles |
| `ListClusters` | `UpdateClusterConfig` / `UpdateClusterVersion` |
| `DeleteCluster` | Add-ons |
| `TagResource` / `UntagResource` | Identity provider configs |
| `ListTagsForResource` | Access entries & policies, encryption config |

`run.sh` sticks to the left column, so it runs against vanilla Floci every time.

## How it works

`run.sh` is the normal EKS control-plane workflow with `AWS_ENDPOINT_URL=http://localhost:4566` exported up front:

```bash
aws eks create-cluster --name hello-cluster \
  --role-arn arn:aws:iam::000000000000:role/eks-role \
  --resources-vpc-config subnetIds=[],securityGroupIds=[] \
  --kubernetes-version 1.29
```

On real AWS that role and VPC config have to exist first. Floci accepts empty subnet/SG
sets, so you skip the IAM/VPC setup and get a cluster object immediately. The script then
polls `describe-cluster` until `status == ACTIVE`, tags the cluster and reads the tags
back, and confirms it appears in `list-clusters`.

The endpoint override is the whole trick — same as every other Floci lab:

```bash
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
```

Drop `AWS_ENDPOINT_URL` and the same script targets your real account.

### The bonus: kubectl against the k3s node

In real mode (`FLOCI_SERVICES_EKS_MOCK=false`, the default) Floci really does run a
`rancher/k3s` container per cluster — so you *can* drive it with kubectl. But the obvious
command, `aws eks update-kubeconfig`, **does not work against Floci**, and it's worth
understanding why (it's a genuine Phase-1 gap, confirmed in Floci's source):

1. `describe-cluster` returns `endpoint: https://floci-eks-<name>:6443` — a
   **Docker-network DNS name**, because Floci itself runs in a container and reports its
   container-internal endpoint. It doesn't resolve from your host, and the host port it
   *did* publish for the API isn't advertised through the API.
2. Floci extracts only the **CA** from k3s; it returns **no client credentials**, and k3s
   can't validate the `aws eks get-token` bearer token that `update-kubeconfig` wires in.
   So even if you reach the endpoint, every call is **401 Unauthorized**.

`deploy-workload.sh` therefore goes to the source of truth instead — it uses the Docker
CLI to pull k3s's own admin kubeconfig (which has the admin client cert/key) out of the
container and repoints it at the host port Floci published for the API server (range
**6500–6599**):

```bash
HOSTPORT=$(docker port floci-eks-hello-cluster 6443 | sed -E 's/.*:([0-9]+)$/\1/')
docker exec floci-eks-hello-cluster cat /etc/rancher/k3s/k3s.yaml > kubeconfig
sed -i -E "s#https://127.0.0.1:6443#https://127.0.0.1:${HOSTPORT}#" kubeconfig
KUBECONFIG=./kubeconfig kubectl get nodes
```

k3s is started with `--tls-san=localhost`, so TLS to `127.0.0.1` validates cleanly. This
needs the **Docker CLI** (to reach the k3s container), which is why it's a separate bonus
script — the control-plane lab above needs none of it.

> Alternatively, run kubectl from a container attached to Floci's Docker network
> (`FLOCI_SERVICES_EKS_DOCKER_NETWORK=<your_net>`), where `floci-eks-<name>:6443`
> resolves — you still need the admin creds from `k3s.yaml`.

## Running Floci differently

Should you launch Floci another way to make the bonus connect more cleanly? Mostly no —
the credential step is a Floci Phase-1 gap, not a deployment setting, so every option
below still ends at "get the admin creds from `k3s.yaml`." For reference:

| How you run Floci | `describe-cluster` endpoint | Effect on this lab |
|---|---|---|
| **Container** (`floci start`) — default | `https://floci-eks-<name>:6443` (Docker DNS) | `deploy-workload.sh` finds the host port via `docker port`. Works. |
| **Native host process** (run the binary; still needs docker.sock for k3s) | `https://localhost:<hostPort>` ✅ | Saves the `docker port` lookup, but you still need `docker exec` for creds. |
| **Container + `FLOCI_SERVICES_EKS_DOCKER_NETWORK=<net>`** + kubectl from a sibling container on that net | `floci-eks-<name>:6443` resolves by DNS | Use this when an **app container** (not just your shell) must reach the cluster. Still needs creds from `k3s.yaml`. |
| **`FLOCI_SERVICES_EKS_MOCK=true`** | `https://localhost:6500` (no k3s) | API shape only — no cluster to deploy to. Good for CI of the control-plane lab. |

Bottom line: the default `floci start` is fine; `deploy-workload.sh` handles the rest.

## Try changing...

- **Tag-driven inventory:** add more `tag-resource` calls and build a `list-clusters` +
  `list-tags-for-resource` report that groups clusters by `team`.
- **Two clusters:** run `CLUSTER=staging ./run.sh` alongside the default and prove
  `aws eks list-clusters` shows both.
- **Pin a version:** run `K8S_VERSION=1.30 ./run.sh` and confirm it via `describe-cluster`.
- **Go declarative:** express the cluster as Terraform (`aws_eks_cluster`) pointed at the
  Floci endpoint and `terraform apply` it instead of the CLI.
- **Bonus, scaled:** once `deploy-workload.sh` reaches the cluster, bump `replicas` in
  `k8s/nginx.yaml` and re-apply, or break it on purpose with `image: nginx:doesnotexist`
  and watch `ImagePullBackOff` — the same failure you'd debug on real EKS.

## Author

[allensanborn](https://github.com/allensanborn)
