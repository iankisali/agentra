# Planner — Orchestrator Agent

The Planner is the entry point for all portfolio analysis. It consumes jobs from SQS, pre-processes the portfolio, and orchestrates the specialist agents (Reporter, Charter, Retirement).

## How It Works

```
SQS message ──▶ Planner Lambda
                    │
                    ├─▶ 1. handle_missing_instruments (call Tagger if needed)
                    ├─▶ 2. update_instrument_prices (Polygon.io)
                    ├─▶ 3. load_portfolio_summary
                    └─▶ 4. LLM agent (Bedrock) decides which specialists to invoke
                              │
                              ├─▶ invoke_reporter   → markdown analysis
                              ├─▶ invoke_charter    → chart configs
                              └─▶ invoke_retirement → projections
                                       │
                                       ▼
                              Aurora `jobs` table
                              (each agent writes to its own JSONB column)
```

## Input

The Planner is triggered by SQS. Message body must contain a job ID:

```json
{
  "job_id": "<uuid>"
}
```

The job must already exist in the `jobs` table with a valid `clerk_user_id`.

## Pre-processing Steps

Before the LLM agent runs, two non-LLM steps execute:

1. **Tagger pre-call** — Scans the user's portfolio for instruments missing allocation data. If any are found, invokes the Tagger Lambda to classify them. Self-healing: as users add new symbols, classifications are auto-generated.

2. **Price refresh** — Fetches current prices for all unique symbols in the portfolio via Polygon.io. Updates the `instruments.current_price` column. Falls back to random prices if `POLYGON_API_KEY` is not set (dev mode only).

## Specialist Agent Tools

The orchestrator agent has three `function_tool`-decorated tools:

| Tool | Invokes | Purpose |
|---|---|---|
| `invoke_reporter` | `agentra-reporter` Lambda | Generate markdown portfolio analysis |
| `invoke_charter` | `agentra-charter` Lambda | Create visualization data |
| `invoke_retirement` | `agentra-retirement` Lambda | Calculate retirement projections |

The LLM decides which to invoke based on the job context.

## Environment Variables

| Variable | Description |
|---|---|
| `AURORA_CLUSTER_ARN`, `AURORA_SECRET_ARN`, `DATABASE_NAME` | Database access |
| `BEDROCK_MODEL_ID`, `BEDROCK_REGION` | LLM configuration |
| `TAGGER_FUNCTION` / `REPORTER_FUNCTION` / `CHARTER_FUNCTION` / `RETIREMENT_FUNCTION` | Specialist Lambda names |
| `POLYGON_API_KEY`, `POLYGON_PLAN` | Market data (optional, falls back to random) |
| `MOCK_LAMBDAS` | Set to `"true"` for local testing without deployed specialists |
| `LANGFUSE_*`, `OPENAI_API_KEY` | Observability |

## Local Testing

```bash
uv sync
uv run test_simple.py
```

The test harness creates a test user, a test job, and runs the handler synchronously.

## Deployment

```bash
cd ../  # to backend/
uv run package_layer.py
uv run package_handlers.py
cd ../terraform/6_agents
terraform apply
```

## How It Fits Into Agentra

The Planner is the front door for all analysis requests. The API layer (or scheduler) writes a job to the `jobs` table and pushes its ID to SQS. The Planner picks it up, coordinates the specialists, and writes results back. Frontend polls the job until `status = completed`, then renders the four JSONB payloads.
