# EC2: open ports in-flight

> Launch a local EC2 instance, then open and close ports on it while it runs, with no restart and no rebuild, and watch the socat sidecars appear and vanish.

## What it shows

- Floci's EC2 is not a mock: `RunInstances` launches a real Docker container with UserData and IMDS
- `authorize-security-group-ingress` on a **running** instance makes the port reachable from your host, live
- How it works under the hood: one tiny `alpine/socat` sidecar container per opened port (`floci-ec2-fwd-<instanceId>-<port>`), so the instance container is never touched
- The guardrails: port 22 is never re-forwarded, only CIDR-sourced rules are published, allow-all ranges are refused

Background reading: [Opening EC2 ports in-flight with socat](https://floci.io/blog/opening-ec2-ports-in-flight-with-socat/).

## Stack

- AWS CLI v2 (plain shell, no SDK code)
- AWS services used: EC2 (RunInstances, security groups), CloudWatch Logs (UserData output)
- Floci EC2 launches real containers, so the Docker socket mount and `-u root` are required

## Run it

EC2 needs the Docker socket and root:

```bash
docker run -d --name floci -p 4566:4566 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -u root floci/floci:latest
```

Then either follow the guided version on [floci.io/labs](https://floci.io/labs/ec2-ports-101/), or run the whole flow in one go:

```bash
./demo.sh
```

## How it works

The demo script:

1. Creates a security group with **no** ingress rules
2. Launches `ami-alpine` (→ `alpine:latest`) with UserData that installs `busybox-extras` and starts busybox `httpd` on port 8080. Alpine's stock busybox has no `httpd` applet, so UserData has to `apk add busybox-extras` first, which means the instance needs outbound network
3. Shows that nothing is reachable: `docker ps` has no `floci-ec2-fwd-*` containers
4. Calls `authorize-security-group-ingress` for 8080. Floci reconciles the security group against live forwards and starts a `floci-ec2-fwd-<instanceId>-8080` sidecar publishing a host port from the 30000-30999 range
5. `curl`s the app through the forwarded host port
6. Revokes the rule. The sidecar is removed and the host port released
7. Tries an allow-all `0-65535` rule to show the guardrail: no sidecar storm, wide spans are skipped (per-instance cap is 20 by default)

The interesting part is what *doesn't* happen: the instance container is never recreated or restarted. Docker only publishes ports at container creation, so Floci moves the mutable part (the forwards) out of the immutable part (the instance).

## Try changing...

- Open a second port (add another `httpd -p 9090 -h /www` to UserData) and watch a second sidecar appear
- Reference another security group as the ingress source instead of a CIDR: no sidecar appears, because that means private-IP reachability in AWS, not host reachability
- Restart the Floci container and check `docker ps`: persisted forwards are recreated from the saved mapping
- Swap `ami-alpine` for `ami-ubuntu2204` or `ami-amazonlinux2023` (unknown `ami-*` IDs fall back to Amazon Linux 2023)

## Author

Hector Ventura · [LinkedIn](https://www.linkedin.com/in/hectorvent/) · [floci.io](https://floci.io)
