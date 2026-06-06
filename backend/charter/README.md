# Charter — Portfolio Visualization Agent

Generates structured chart data (configs + data points) for portfolio dashboards. Outputs are consumed directly by the frontend chart library.

## How It Works

```
job_id ──▶ Charter Lambda
              │
              ├─▶ 1. Load portfolio (accounts, positions, instruments)
              ├─▶ 2. Calculate aggregations (top holdings, sector totals, etc.)
              ├─▶ 3. Bedrock formats into chart configs with colors
              └─▶ 4. Write to jobs.charts_payload
```

## Charts Generated

The agent always produces five charts:

| Chart Name | Type | Description |
|---|---|---|
| `top_holdings` | horizontalBar | Largest positions by USD value |
| `account_types` | pie | Distribution across 401k, IRA, Taxable, etc. |
| `sector_breakdown` | donut | Allocation across industry sectors |
| `geographic_exposure` | bar | Investment allocation by region |
| `asset_class_distribution` | pie | Equity vs. fixed income vs. cash vs. real estate |

## Input

```json
{
  "job_id": "<uuid>"
}
```

## Output

Stored in `jobs.charts_payload`:

```json
{
  "agent": "charter",
  "charts": [
    {
      "name": "top_holdings",
      "title": "Top Holdings",
      "type": "horizontalBar",
      "description": "Largest positions in the portfolio",
      "data": [
        {"label": "SPY", "value": 45000.00, "color": "#3B82F6"},
        {"label": "QQQ", "value": 20000.00, "color": "#10B981"}
      ]
    },
    ...
  ],
  "generated_at": "2026-04-28T18:23:53.269352+00:00"
}
```

## Color Palette

A standard color palette is used to keep visuals consistent across users:
- Blue (`#3B82F6`), Green (`#10B981`), Purple (`#8B5CF6`), Cyan (`#0891B2`), Indigo (`#6366F1`), Red (`#EF4444`)

The palette is defined in `templates.py` — don't override it per chart.

## Environment Variables

| Variable | Description |
|---|---|
| `AURORA_CLUSTER_ARN`, `AURORA_SECRET_ARN`, `DATABASE_NAME` | Database access |
| `BEDROCK_MODEL_ID`, `BEDROCK_REGION` | LLM configuration |
| `LANGFUSE_*`, `OPENAI_API_KEY` | Observability |

## Local Testing

```bash
uv sync
uv run test_simple.py
```

## Deployment

```bash
cd ../  # to backend/
uv run package_layer.py
uv run package_handlers.py
cd ../terraform/6_agents
terraform apply
```

## How It Fits Into Agentra

The Charter is one of three specialist agents invoked by the Planner. The Reporter generates narrative analysis, the Retirement agent handles projections, and the Charter generates the visualization data that the frontend dashboard renders.
