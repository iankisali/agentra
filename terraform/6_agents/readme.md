# AI Agents Infrastructure

This Terraform module deploys Agentra's multi-agent system — five specialized Lambda functions coordinated through SQS, sharing a single Lambda Layer for dependencies.

## Architecture

```
                    SQS (analysis-jobs)
                          │
                          ▼
                  ┌──────────────┐
                  │   Planner    │  (orchestrator, 15 min timeout, 2 GB)
                  │ Lambda+Layer │
                  └──────┬───────┘
                         │ invokes
        ┌────────────────┼────────────────┬──────────────┐
        ▼                ▼                ▼              ▼
  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
  │  Tagger  │    │ Reporter │    │ Charter  │    │Retirement│
  │  Lambda  │    │  Lambda  │    │  Lambda  │    │  Lambda  │
  └──────────┘    └──────────┘    └──────────┘    └──────────┘
        │                │                │              │
        └────────────────┼────────────────┴──────────────┘
                         ▼
                   Aurora (jobs table)
                   each agent writes to its own JSONB column
```

All 5 agents share a single Lambda Layer (`agentra-shared-deps`) containing common dependencies (litellm, openai-agents, langfuse, boto3, pydantic). This keeps individual function zips tiny (~16 KB each) while staying under Lambda's 250 MB unzipped size limit.

## What It Deploys

| Resource | Description |
|---|---|
| **SQS Queue** (`analysis_jobs`) | Async job queue for portfolio analysis requests, 15 min visibility timeout |
| **SQS DLQ** | Dead letter queue, 3 receive attempts before failure |
| **S3 Bucket** | Stores Lambda packages and the shared layer zip |
| **Lambda Layer** (`agentra-shared-deps`) | Shared Python dependencies (~167 MB unzipped) for all 5 agents |
| **Planner Lambda** | Orchestrator agent (`agentra-planner`), 15 min timeout, 2 GB RAM, SQS-triggered |
| **Tagger Lambda** | Instrument classifier (`agentra-tagger`), 5 min timeout, 1 GB RAM |
| **Reporter Lambda** | Portfolio analysis writer (`agentra-reporter`), 5 min timeout, 1 GB RAM |
| **Charter Lambda** | Visualization generator (`agentra-charter`), 5 min timeout, 1 GB RAM |
| **Retirement Lambda** | Retirement projections (`agentra-retirement`), 5 min timeout, 1 GB RAM |
| **IAM Role** | Single shared role with permissions for Aurora Data API, Bedrock, S3 Vectors, SageMaker, SQS, Lambda invocation |
| **CloudWatch Log Groups** | One per agent, 7-day retention |

## How It Fits Into Agentra

The Planner is the entry point — it pulls jobs from SQS, calls the Tagger to classify any unknown instruments, fetches market prices via Polygon, then orchestrates the Reporter, Charter, and Retirement agents. Each specialist agent writes its output to a dedicated JSONB column in the `jobs` table.

## Dependencies

This module depends on:
- **`terraform/1_sagemaker`** — SageMaker embedding endpoint (used by Reporter for vector search)
- **`terraform/2_ingest`** — S3 Vectors bucket (queried for market context)
- **`terraform/5_database`** — Aurora cluster + secret (where job results are stored)

## Configuration

| Variable | Description | Default |
|---|---|---|
| `aws_region` | AWS region | — (required) |
| `aws_profile` | AWS CLI profile | `"default"` |
| `aurora_cluster_arn` | Aurora cluster ARN from `5_database` | — (required) |
| `aurora_secret_arn` | Aurora credentials secret ARN | — (required) |
| `vector_bucket` | S3 Vectors bucket name from `2_ingest` | — (required) |
| `sagemaker_endpoint` | SageMaker embedding endpoint name | — (required) |
| `bedrock_model_id` | Bedrock inference profile (e.g. `us.amazon.nova-pro-v1:0`) | — (required) |
| `bedrock_region` | Region for Bedrock inference | `us-east-1` |
| `polygon_api_key` | Polygon.io API key for market prices | — (optional) |
| `polygon_plan` | `"paid"` or `"free"` (controls real-time vs EOD) | `"free"` |
| `langfuse_public_key` | LangFuse public key for tracing | — (optional) |
| `langfuse_secret_key` | LangFuse secret key for tracing | — (optional) |
| `langfuse_host` | LangFuse host URL | `https://cloud.langfuse.com` |
| `openai_api_key` | OpenAI key (used by Agents SDK for tracing only) | — (required) |

## Outputs

| Output | Description |
|---|---|
| `sqs_queue_url` | SQS queue URL for submitting jobs |
| `sqs_queue_arn` | SQS queue ARN |
| `lambda_function_names` | Map of agent → Lambda function name |
| `setup_instructions` | Multi-line setup and test guide |

## Deployment Workflow

The packaging is split into two steps to keep each Lambda zip under the 250 MB unzipped limit:

```bash
# 1. Build the shared dependency layer (one-time, rebuild when deps change)
cd backend
uv run package_layer.py

# 2. Build slim handler zips (rebuild when agent code changes)
uv run package_handlers.py

# 3. Deploy infrastructure + functions
cd ../terraform/6_agents
terraform init
terraform apply
```

## Testing

After deployment, send a test job to SQS and watch CloudWatch:

```bash
# Submit a job (replace with a real user_id and job_id from your DB)
aws sqs send-message \
  --queue-url <sqs_queue_url> \
  --message-body '{"job_id": "<job-uuid>"}' \
  --region us-east-1 --profile ai

# Watch logs
aws logs tail /aws/lambda/agentra-planner --follow --region us-east-1 --profile ai
```

## Cost Notes

- Lambda costs are pay-per-invocation; idle = $0
- The shared layer is downloaded once per cold start (no per-invocation cost)
- The DLQ adds minimal cost; failed jobs accumulate there for inspection
- CloudWatch Logs retention is 7 days to limit storage costs
