# Reporter — Portfolio Analysis Agent

Generates a markdown portfolio analysis report for a given job. Includes executive summary, composition breakdown, asset allocation, and personalized recommendations.

## How It Works

```
job_id ──▶ Reporter Lambda
              │
              ├─▶ 1. Load user + accounts + positions + instruments from Aurora
              ├─▶ 2. Calculate portfolio metrics (total value, positions, etc.)
              ├─▶ 3. Pull market context from S3 Vectors (SageMaker embedding)
              ├─▶ 4. Bedrock generates markdown analysis
              ├─▶ 5. Judge agent evaluates quality (0-100 score)
              └─▶ 6. Write to jobs.report_payload
```

## Input

```json
{
  "job_id": "<uuid>"
}
```

## Output

The report is stored in the `jobs.report_payload` JSONB column:

```json
{
  "agent": "reporter",
  "content": "## Investment Portfolio Analysis Report\n\n### Executive Summary\n- ...",
  "generated_at": "2026-04-28T18:23:53.269352+00:00",
  "evaluation": {
    "score": 87,
    "feedback": "Strong analysis with clear recommendations..."
  }
}
```

## Report Structure

The markdown report typically includes:

- **Executive Summary** — High-level findings (3-5 bullets)
- **Portfolio Composition Analysis** — Holdings, account distribution
- **Asset Allocation Review** — Equity/bond/cash breakdown vs. targets
- **Geographic & Sector Exposure** — Diversification assessment
- **Recommendations** — Actionable next steps tailored to the user's retirement timeline
- **Risk Considerations** — Concentration risk, time horizon, rebalancing needs

## Self-Evaluation

After generating the report, a separate judge agent evaluates it on a 0-100 scale. The score and feedback are logged for quality monitoring but don't block the report from being saved.

## Environment Variables

| Variable | Description |
|---|---|
| `AURORA_CLUSTER_ARN`, `AURORA_SECRET_ARN`, `DATABASE_NAME` | Database access |
| `BEDROCK_MODEL_ID`, `BEDROCK_REGION` | LLM configuration |
| `SAGEMAKER_ENDPOINT` | Embedding endpoint for semantic search |
| `LANGFUSE_*`, `OPENAI_API_KEY` | Observability |

## Local Testing

```bash
uv sync
uv run test_simple.py
```

The test creates a test user with a sample portfolio, runs the agent, verifies the report was stored, then cleans up.

## Deployment

```bash
cd ../  # to backend/
uv run package_layer.py
uv run package_handlers.py
cd ../terraform/6_agents
terraform apply
```

## How It Fits Into Agentra

The Reporter is one of three specialist agents invoked by the Planner. While the Charter handles visualizations and the Retirement agent handles long-term projections, the Reporter focuses on narrative analysis that the user reads. All three write to separate JSONB columns in the same `jobs` row.
