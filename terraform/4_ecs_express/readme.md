# ECS Express Mode — Researcher Service (Test)

This is a **test module** to evaluate AWS ECS Express Mode as a replacement for App Runner, which is no longer accepting new customers as of April 30, 2026.

## What Is ECS Express Mode?

ECS Express Mode simplifies deploying containerized applications by automating infrastructure setup. You provide:
1. A container image
2. A task execution role
3. An infrastructure role

ECS Express Mode automatically provisions:
- Application Load Balancer with SSL/TLS
- Security groups
- Auto scaling policies
- CloudWatch logging
- A unique URL (`servicename.ecs.region.on.aws`)

## What This Module Deploys

Terraform manages the IAM roles only. The ECS Express service itself is created via the AWS CLI (the Terraform AWS provider doesn't support `aws_ecs_express_gateway_service` yet in v5.x).

| Resource | Managed By | Description |
|---|---|---|
| **IAM Role (Task Execution)** | Terraform | Allows ECS to pull images from ECR and write CloudWatch logs |
| **IAM Role (Infrastructure)** | Terraform | Allows ECS Express to provision ALB, security groups, scaling |
| **IAM Role (Task)** | Terraform | Runtime role with Bedrock InvokeModel permissions |
| **ECS Express Gateway Service** | AWS CLI (`deploy-ecs-express.sh`) | The researcher container (1 vCPU, 2 GB, port 8000, `/health` check) |

## Prerequisites

- The ECR repository `agentra-researcher` must already exist (created by `terraform/3_researcher`)
- A Docker image must be pushed to ECR (use `backend/researcher/deploy.py`)
- AWS CLI must support `ecs create-express-gateway-service` (latest version)

## Usage

```bash
# Step 1: Create IAM roles
terraform init
terraform apply

# Step 2: Deploy the ECS Express service
./deploy-ecs-express.sh
```

After deployment, test with:

```bash
curl https://agentra-researcher.ecs.us-east-1.on.aws/health
```

## Comparison: App Runner vs ECS Express Mode

| Feature | App Runner | ECS Express Mode |
|---|---|---|
| Container image source | ECR | ECR or private registry |
| Auto scaling | Built-in | Built-in (configurable min/max) |
| Load balancer | Managed (hidden) | ALB (visible, configurable) |
| Custom domain | Supported | Supported |
| Health checks | TCP only | HTTP path-based |
| IAM roles | 2 (access + instance) | 3 (execution + infrastructure + task) |
| URL format | `*.awsapprunner.com` | `*.ecs.region.on.aws` |
| Status | Deprecated (no new customers) | Active, recommended |

## Notes

- This is on branch `feat/ecs-express` — does not affect the working App Runner deployment on `main`
- The existing ECR image from `3_researcher` is reused (same Docker image works for both)
- If the Terraform resource schema differs from what's documented, check the AWS provider changelog
