# Agentra Infrastructure (Terraform)

Infrastructure for the Agentra multi-agent financial intelligence platform, split
into numbered layers. Each layer is an independent Terraform root with its own
state. Layers must be applied **in order** because later layers consume the
outputs of earlier ones.

## Layers

| Layer | Provisions | Depends on |
|---|---|---|
| `0_bootstrap` | S3 state bucket + DynamoDB lock table for the remote backend | — (local state) |
| `1_sagemaker` | SageMaker Serverless embedding endpoint (`agentra-embedding-endpoint`) | `0_bootstrap` |
| `2_ingest` | S3 Vectors bucket, ingest Lambda, API Gateway + key | `0_bootstrap`, `1_sagemaker` (endpoint name) |
| `3_researcher` | App Runner service + ECR, optional EventBridge scheduler | `0_bootstrap`, `2_ingest` (API endpoint + key) |
| `4_ecs_express` | **Inactive** — leftover state only, no `.tf` files. Skip. | — |
| `5_database` | Aurora Serverless v2 PostgreSQL, Secrets Manager credentials, Lambda IAM role | `0_bootstrap` |
| `6_agents` | 5 agent Lambdas (planner, tagger, reporter, charter, retirement), SQS queue + DLQ, shared deps layer | `0_bootstrap`, `5_database`, `2_ingest` (via remote state) |
| `7_frontend` | S3 + CloudFront frontend hosting, API Lambda | `0_bootstrap`, `5_database`, `6_agents` (via remote state) |

Reusable modules live in `modules/` (currently `modules/agent-lambda`, used by `6_agents`).

## State

All application layers use a shared **S3 remote backend** with **DynamoDB state
locking**, provisioned by the `0_bootstrap` layer:

- **Bucket:** `agentra-tfstate-<account_id>` (versioned, AES256-encrypted, public access blocked)
- **Lock table:** `agentra-tfstate-locks` (DynamoDB, `LockID` hash key)
- **Key per layer:** `<layer>/terraform.tfstate` (e.g. `5_database/terraform.tfstate`)

Each layer declares this in its `terraform { backend "s3" { ... } }` block. The
`0_bootstrap` layer itself uses the **local backend** by design — it creates the
bucket and table that everything else depends on, so it can't use them.

`6_agents` and `7_frontend` read upstream outputs through `terraform_remote_state`
data sources pointing at the **same S3 bucket** (not local paths), so upstream
layers must be applied before downstream layers.

### First-time backend setup

Before applying any application layer, create the backend infrastructure once:

```bash
export AWS_PROFILE=ai
cd terraform/0_bootstrap
terraform init && terraform apply
```

If you are setting up on a fresh machine where layers already have S3 state, just
run `terraform init` in each layer — Terraform will connect to the existing
remote state automatically.

## Prerequisites

- Terraform `>= 1.5`
- AWS CLI configured with the `ai` profile (`aws sts get-caller-identity --profile ai`)
- Docker running (backend packaging for ingest/agents/api Lambdas and the researcher image)
- `uv` (for the backend packaging and database scripts)
- Secrets files in place for layers that need them (see below)

Export the profile once for the whole session:

```bash
export AWS_PROFILE=ai
```

### Secrets

Layers `3_researcher` and `6_agents` read secrets from a gitignored
`secrets.auto.tfvars` file. Copy the example and fill in real values before
applying:

```bash
cp terraform/3_researcher/secrets.auto.tfvars.example terraform/3_researcher/secrets.auto.tfvars
cp terraform/6_agents/secrets.auto.tfvars.example     terraform/6_agents/secrets.auto.tfvars
```

| Layer | Secret keys |
|---|---|
| `3_researcher` | `openai_api_key`, `agentra_api_key` |
| `6_agents` | `polygon_api_key`, `openai_api_key`, (optional) `langfuse_*` |

## Deploy order

Each layer is applied from its own directory. The first time in a layer, run
`terraform init`.

```bash
export AWS_PROFILE=ai

# 0. Backend (one-time) — S3 state bucket + DynamoDB lock table
cd terraform/0_bootstrap
terraform init && terraform apply

# 1. SageMaker embedding endpoint
cd ../1_sagemaker
terraform init && terraform apply

# 2. Ingestion pipeline (S3 Vectors + API Gateway)
#    Uses sagemaker_endpoint_name (default: agentra-embedding-endpoint)
cd ../2_ingest
terraform init && terraform apply

# 3. Researcher (App Runner + ECR)
#    Requires backend image pushed to ECR (see backend/researcher/deploy.py)
#    and agentra_api_endpoint set in terraform.tfvars
cd ../3_researcher
terraform init && terraform apply

# (4_ecs_express is inactive — skip)

# 5. Database (Aurora Serverless v2 + Secrets Manager)
cd ../5_database
terraform init && terraform apply

# 6. Agents (5 Lambdas + SQS)
#    Auto-reads Aurora ARNs from 5_database and vector bucket from 2_ingest
#    Requires backend packages built: backend/shared_layer.zip and
#    backend/<agent>/<agent>_lambda.zip
cd ../6_agents
terraform init && terraform apply

# 7. Frontend (S3 + CloudFront + API Lambda)
#    Auto-reads from 5_database and 6_agents
cd ../7_frontend
terraform init && terraform apply
```

## Post-deploy: database schema & seed

After `5_database` is up, create the schema and load reference data using the
Data API scripts (no direct Postgres connection needed):

```bash
cd backend/database
uv sync
uv run run_migration.py          # create tables, indexes, triggers
uv run seed_data.py              # load 22 ETF instruments
uv run verify_db.py              # verify
# or, for a full dev reset with a test user/portfolio:
uv run reset_db.py --with-test-data
```

## Backend packaging (build artifacts before apply)

Some layers expect zipped Lambda artifacts to exist locally:

- `2_ingest` → `backend/ingest/lambda_function.zip`
- `6_agents` → `backend/shared_layer.zip` and `backend/<agent>/<agent>_lambda.zip`
- `7_frontend` / API → `backend/api/api_lambda.zip`

These are produced by each backend component's `package_docker.py` (run with `uv`).
The higher-level `scripts/deploy.py` handles packaging + frontend build + S3 sync +
CloudFront invalidation for the API/frontend portion, but does not orchestrate all
seven layers — use the per-layer `terraform apply` order above for full infra setup.

## Tear down

Destroy in reverse order (`7 → 6 → 5 → 3 → 2 → 1`) to respect dependencies:

```bash
cd terraform/7_frontend && terraform destroy
cd ../6_agents          && terraform destroy
cd ../5_database        && terraform destroy
cd ../3_researcher      && terraform destroy
cd ../2_ingest          && terraform destroy
cd ../1_sagemaker       && terraform destroy
```

> `0_bootstrap` is intentionally **not** destroyed here — it holds the remote
> state for every other layer. The state bucket has `prevent_destroy = true`.
> Only tear it down after all other layers are destroyed, and you'll need to
> remove the `prevent_destroy` lifecycle guard first.
