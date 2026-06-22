# Agentra

**Agentra** is a production-grade, agentic AI SaaS platform for portfolio analysis, financial advisory, and retirement planning.

It uses a multi-agent architecture on AWS serverless infrastructure to continuously analyze financial data, generate insights, and optimize user financial outcomes.

---

## Architecture

```
User → CloudFront → S3 (Next.js)
                  → API Gateway → API Lambda → SQS
                                                 ↓
                                          Planner (Orchestrator)
                                        ┌────┼────┬────┐
                                    Reporter Charter Retirement Tagger
                                        │       │        │        │
                                        └───────┴────────┴────────┘
                                                    ↓
                              ┌──────────────────────────────────────┐
                              │  Aurora PostgreSQL  │  AWS Bedrock   │
                              │  S3 Vectors        │  SageMaker     │
                              └──────────────────────────────────────┘
```

See `assets/agentra-architecture.drawio` for the full diagram.

---

## Features

- **Multi-Agent System** — Coordinated agents with single-responsibility design
  - Planner (orchestration & task decomposition)
  - Reporter (portfolio analysis & RAG)
  - Retirement (long-term financial projections)
  - Tagger (asset classification & enrichment)
  - Charter (visualization & chart generation)
  - Researcher (market intelligence via App Runner)

- **Portfolio Intelligence** — Performance analysis, risk assessment, diversification insights

- **Retirement Planning** — Scenario modeling, goal tracking, financial projections

- **Cloud-Native & Serverless** — Lambda, SQS, Aurora Serverless v2, Bedrock, App Runner

- **SaaS Platform** — Multi-tenant with Clerk auth, secure data isolation, Next.js dashboard

---

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Next.js, Tailwind CSS, Recharts |
| API | AWS API Gateway (HTTP) + Lambda (Python/FastAPI) |
| Auth | Clerk (JWT validation in Lambda) |
| Agents | OpenAI Agents SDK, LiteLLM, AWS Bedrock (Nova Pro) |
| Queue | SQS (async job processing) |
| Database | Aurora Serverless v2 PostgreSQL (Data API) |
| Embeddings | SageMaker Serverless (sentence-transformers) |
| Vectors | S3-based vector storage |
| Market Data | Polygon.io |
| Observability | Langfuse |
| Infrastructure | Terraform (modularized, S3 remote state) |
| Deployment | Docker (Lambda packaging), App Runner (Researcher) |

---

## Project Structure

```
backend/
├── agents/          # Agent design docs (AGENTS.md per agent)
├── api/             # API Lambda (FastAPI + Mangum)
├── charter/         # Charter agent
├── core/            # Shared models, config, utils
├── database/        # Schema, migrations, seed data
├── ingest/          # Ingestion Lambda (vectors)
├── planner/         # Planner/Orchestrator agent
├── reporter/        # Reporter agent
├── researcher/      # Researcher (App Runner service)
├── retirement/      # Retirement agent
└── tagger/          # Tagger agent

frontend/            # Next.js SaaS dashboard

terraform/
├── 0_bootstrap/     # S3 state bucket + DynamoDB lock table
├── 1_sagemaker/     # Embedding endpoint
├── 2_ingest/        # Ingestion pipeline + API Gateway
├── 3_researcher/    # App Runner + ECR
├── 5_database/      # Aurora Serverless v2 + Secrets Manager
├── 6_agents/        # 5 agent Lambdas + SQS + shared layer
├── 7_frontend/      # S3 + CloudFront + API Lambda
└── modules/
    └── agent-lambda/  # Reusable module for agent Lambda resources

scripts/             # deploy.py, run_local.py
assets/              # Architecture diagrams
```

---

## Quick Start

### Prerequisites

- AWS CLI configured (profile: `ai`)
- Terraform >= 1.5
- Docker (for Lambda packaging)
- `uv` (Python package manager)
- Node.js 18+ (frontend)

### Infrastructure

Deploy in order (see `terraform/README.md` for full details):

```bash
export AWS_PROFILE=ai

cd terraform/0_bootstrap && terraform init && terraform apply   # State backend
cd ../1_sagemaker       && terraform init && terraform apply   # Embeddings
cd ../2_ingest          && terraform init && terraform apply   # Ingest pipeline
cd ../3_researcher      && terraform init && terraform apply   # Researcher
cd ../5_database        && terraform init && terraform apply   # Database
cd ../6_agents          && terraform init && terraform apply   # Agent Lambdas
cd ../7_frontend        && terraform init && terraform apply   # Frontend hosting
```

### Database Setup

```bash
cd backend/database
uv sync
uv run run_migration.py    # Create schema
uv run seed_data.py        # Load instruments
uv run verify_db.py        # Verify
```

### Frontend

```bash
cd frontend
npm install
npm run dev                # Local development
npm run build              # Production build
```

### Deploy (full)

```bash
cd scripts
AWS_PROFILE=ai uv run deploy.py
```

---

## Development Workflow

- Feature branches: `feature/*`
- Production branch: `main`
- All changes via PR with CI checks

---

## Key Design Decisions

1. **Agent isolation** — Each agent is a separate Lambda with single responsibility
2. **Event-driven** — SQS decouples the API from agent execution
3. **Remote state** — S3 backend with DynamoDB locking for team collaboration
4. **No hardcoded secrets** — Secrets in AWS Secrets Manager or gitignored `secrets.auto.tfvars`
5. **Modular Terraform** — Reusable `agent-lambda` module, `for_each` over agent configs
6. **Data API** — Aurora accessed via Data API (no VPC/NAT needed for Lambda)

---

## Environments

| Environment | Purpose |
|---|---|
| `dev` | Active development |
| `staging` | Pre-production validation |
| `prod` | Live system |

---

## Status

Agentra is in active development with core infrastructure and agents deployed:

- Infrastructure: fully provisioned and managed via Terraform
- Agents: planner, reporter, charter, retirement, tagger deployed and functional
- Frontend: Next.js dashboard deployed via CloudFront + S3
- Observability: Langfuse integration (traces in progress)

---

## License

See [LICENSE](LICENSE).
