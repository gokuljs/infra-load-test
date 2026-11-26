# Node.js vs Go HTTP experiments

This repository will compare separate Node.js and Go HTTP servers using the same request workloads. The Node.js server comes first; Go code and measured results will be added later.

## Node.js server

The Fastify server lives in [`nodejs/`](nodejs/). It requires Node.js 20 or newer and serves plain HTTP. From the repository root:

```sh
cd nodejs
npm ci
npm start
```

It listens on `127.0.0.1:3000` by default. Set `HOST` and `PORT` to change the bind address, for example `HOST=0.0.0.0 PORT=3001 npm start`. Request logging is disabled so it does not add work to each request. Run the route tests with `npm test` from `nodejs/`.

## Endpoint contract

These fixed responses define the initial workloads for a later Go server. `/healthz` is a readiness check, not a benchmark workload.

| Method | Path | Success response |
| --- | --- | --- |
| GET | `/healthz` | `200` JSON `{"status":"ok"}` |
| GET | `/api/ping` | `200` plain text `pong` |
| GET | `/api/json` | `200` JSON `{"message":"ok"}` |
| GET | `/api/payload` | `200` binary body: exactly 1,024 `x` bytes |
| POST | `/api/echo` | `200` JSON object matching the request body |

`POST /api/echo` accepts JSON objects up to 64 KiB. It returns `400` for other JSON types and `413` for an oversized body.

Example requests after starting the server:

```sh
curl http://127.0.0.1:3000/healthz
curl http://127.0.0.1:3000/api/ping
curl http://127.0.0.1:3000/api/json
curl -o /dev/null -w '%{size_download}\n' http://127.0.0.1:3000/api/payload
curl -H 'content-type: application/json' -d '{"message":"hello"}' http://127.0.0.1:3000/api/echo
```

The package lockfile pins `light-my-request` to a Node.js 20-compatible release; newer releases pull a `cookie` version that requires Node.js 22. No throughput or capacity claim is made before a workload and environment are measured and recorded.

## AWS lab deployment

From the repository root, run Terraform with the AWS CLI configured for the lab account and Docker installed with Buildx available. When a build is needed on macOS, the publish script starts Docker Desktop automatically for the local `desktop-linux` or `default` context and allows up to 120 seconds for startup. It verifies the engine is ready before building. Set up Docker Desktop once before the first apply, including any initial prompts.

```sh
terraform -chdir=infra/bootstrap init
terraform -chdir=infra/bootstrap apply
```

Apply creates ECR and, on the first run or when the app build inputs change, publishes a `linux/amd64` image and records its ECR digest in `/1million/lab/app-image-digest`. Terraform verifies that digest in ECR before it creates or updates the launch template. An apply with unchanged build inputs reuses the published image. Existing EC2 instances pick up a new image when replaced.

If Docker Desktop startup fails, open it with `open -a Docker`, wait until `docker info` succeeds, and rerun the same apply. For remote Docker engines and other contexts, restore the selected engine's connection before retrying. An existing image tag can be reused without starting Docker. A failed build or push leaves the SSM digest at its previous value.

`terraform -chdir=infra/bootstrap destroy` still removes ECR and its images. The next apply recreates the repository, publishes the image, and writes the new digest before EC2 starts. If an image is deleted from ECR outside Terraform while the repository still exists, run `terraform -chdir=infra/bootstrap apply -replace=terraform_data.app_image` to publish it again.

### SSH access

Terraform allows inbound TCP port 22 to the app machines from `api_client_cidr` in `infra/bootstrap/terraform.tfvars`. Set it to your current public IPv4 address followed by `/32`. You can check your address with `curl -4 -fsS https://checkip.amazonaws.com`. Update the value and apply whenever your public IP changes. The SSH rule applies to existing machines and future Auto Scaling launches.

If you already added an identical SSH rule manually, find its `sgr-...` security group rule ID and import it before applying. The rule must match the app security group, TCP port 22, and the configured client CIDR. Replace `sgr-EXISTING_RULE_ID` with that rule's ID.

```sh
terraform -chdir=infra/bootstrap import aws_vpc_security_group_ingress_rule.ssh sgr-EXISTING_RULE_ID
```

Run `terraform -chdir=infra/bootstrap apply` to create or update the SSH rule. Connect from your Mac using AWS CLI v2 and EC2 Instance Connect, replacing `i-INSTANCE_ID` with an app instance ID.

```sh
aws ec2-instance-connect ssh \
  --region us-east-1 \
  --instance-id i-INSTANCE_ID \
  --os-user ec2-user \
  --connection-type direct
```

EC2 Instance Connect supplies a temporary SSH key for each connection. Your AWS CLI identity needs `ec2:DescribeInstances` and `ec2-instance-connect:SendSSHPublicKey` permissions for the target instance.
