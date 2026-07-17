# DevOps AWS Automation Lab — High-Level Architecture

Companion guide for `architecture-diagram.drawio`.

## What it shows

A minimal, high-level view of the resources this project's Bash/AWS CLI scripts provision, and how traffic and provisioning calls flow between them.

## Flow

1. **Operator** runs the Bash scripts (`run_all.sh` → `create_security_group.sh`, `create_ec2.sh`, `create_s3_bucket.sh`) locally via the AWS CLI.
2. The CLI authenticates as **`devops-lab-user`**, an IAM identity scoped to a least-privilege policy (EC2 in `us-east-1` only, S3 actions limited to `devops-lab-*` buckets).
3. That identity **provisions and manages** the EC2 instance, its security group, and the S3 bucket.
4. At launch time, the EC2 instance's AMI is resolved via an **SSM Parameter Store** lookup (`/aws/service/ami-amazon-linux-latest/...`) — a one-time, provision-time call, not runtime traffic.
5. Once running, the **EC2 instance** (`devops-lab-instance`, t3.micro, Amazon Linux 2) sits inside a **Security Group** (`devops-sg`) that allows:
   - SSH (22) only from the operator's detected public IP
   - HTTP (80) from anywhere, since the instance is meant to serve public web traffic
6. The **Operator** connects over SSH for management; **Internet users** reach the instance over HTTP.
7. The **S3 bucket** (`devops-lab-<account-id>`) is separate from the VPC — versioned, encrypted, public access blocked, with a deny-insecure-transport policy.

## Services used

| Service | Purpose |
|---|---|
| IAM | Least-privilege identity (`devops-lab-user`) used by the CLI to provision everything |
| EC2 | Single `t3.micro` Amazon Linux 2 instance (`devops-lab-instance`) |
| Security Group | `devops-sg` — SSH restricted to operator IP, HTTP open |
| S3 | Versioned, encrypted bucket with public access blocked |
| SSM Parameter Store | Resolves the latest Amazon Linux 2 AMI ID at provisioning time |
| VPC / Public Subnet | Pre-existing default VPC/subnet the instance launches into |

## Key design decisions reflected in the diagram

- **IAM is the single entry point** into AWS — nothing in the diagram bypasses the least-privilege policy.
- **SSM is drawn as a dashed, provision-time-only link** — it's not part of the running system's data path.
- **The Security Group is drawn as its own boundary** around EC2 to make the SSH/HTTP rule split visible at a glance, without dropping into per-script flowchart detail.
- **S3 sits outside the VPC boundary** in the diagram, matching reality — S3 is a regional service, not a VPC resource.
