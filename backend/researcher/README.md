# Researcher — Autonomous Investment Research Agent

This module contains the Agentra Researcher, an autonomous agent that browses financial websites, analyzes market data, and stores structured research in the Agentra knowledge base.

## How It Works

The researcher is a FastAPI service running on AWS App Runner. When triggered, it:

1. Launches a headless browser (Playwright MCP) to navigate financial sources
2. Uses Claude 3.7 Sonnet (via AWS Bedrock) to analyze the data
3. Stores structured findings in the vector database via the ingest API

```
Trigger (API call or EventBridge)
    ↓
FastAPI Server (App Runner)
    ↓
Agent (OpenAI Agents SDK + LiteLLM)
    ├── Playwright MCP → Browse Yahoo Finance, Reuters, etc.
    ├── Claude 3.7 Sonnet (Bedrock) → Analyze data
    └── ingest_financial_document → Store in S3 Vectors
    ↓
Traces → OpenAI Traces Dashboard
```

## Key Files

| File | Purpose |
|---|---|
| `server.py` | FastAPI app with `/research`, `/research/auto`, and `/health` endpoints |
| `context.py` | Agent system prompt and default research query |
| `tools.py` | `ingest_financial_document` tool — sends analysis to the ingest API |
| `mcp_servers.py` | Playwright MCP server config for headless browsing |
| `deploy.py` | Build, push to ECR, and update App Runner service |
| `test-local.py` | Run the agent locally against Bedrock (same config as production) |
| `Dockerfile` | Production container — Python 3.12, Node.js 20, Playwright Chromium |

## API Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/health` | Health check with config status |
| `POST` | `/research` | Run research on a specific topic (`{"topic": "NVDA stock"}`) |
| `GET` | `/research/auto` | Auto-pick a trending topic and research it (used by scheduler) |

## Environment Variables

| Variable | Description |
|---|---|
| `AWS_DEFAULT_REGION` | AWS region for Bedrock calls |
| `BEDROCK_MODEL` | LiteLLM model string (default: Claude 3.7 Sonnet) |
| `OPENAI_API_KEY` | Used for agent tracing (OpenAI Traces dashboard) |
| `AGENTRA_API_ENDPOINT` | Ingest API URL (`POST /ingest`) |
| `AGENTRA_API_KEY` | API key for the ingest endpoint |

## Local Development

```bash
# Install dependencies
uv sync

# Install Playwright browser
npx -y playwright install chromium

# Run locally
uv run uvicorn server:app --host 0.0.0.0 --port 8000

# Or test the agent directly
uv run test-local.py
uv run test-local.py "AAPL earnings"
```

## Deployment

```bash
# Build and push Docker image, then update App Runner
uv run deploy.py
```

The deploy script reads config from the project root `.env`, builds for `linux/amd64`, pushes to ECR, and triggers an App Runner deployment.

## Dependencies

- **`terraform/1_sagemaker`** — SageMaker embedding endpoint (used by the ingest pipeline)
- **`terraform/2_ingest`** — Ingest API and S3 Vectors (where research gets stored)
- **`terraform/3_researcher`** — App Runner, ECR, IAM roles for this service

## How It Fits Into Agentra

The Researcher is one of six agents in the Agentra system. It feeds the knowledge base with current market intelligence that the **Reporter Agent** and **Retirement Agent** later query to generate portfolio insights and financial plans.
