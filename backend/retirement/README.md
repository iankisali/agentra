# Retirement — Long-term Projection Agent

Runs a Monte Carlo simulation on the user's portfolio and generates a markdown retirement readiness analysis with success probabilities and recommendations.

## How It Works

```
job_id ──▶ Retirement Lambda
              │
              ├─▶ 1. Load user (years until retirement, target income)
              ├─▶ 2. Load portfolio + calculate current value & allocation
              ├─▶ 3. Run Monte Carlo simulation (multiple trajectories)
              ├─▶ 4. Compute success rate for sustaining target income
              ├─▶ 5. Bedrock generates structured markdown analysis
              └─▶ 6. Write to jobs.retirement_payload
```

## Simulation Model

- **Time horizon** — `users.years_until_retirement` (default 25)
- **Target annual income** — `users.target_retirement_income` (default $80k)
- **Asset class assumptions**:
  - Equity: 7% mean return, 15% volatility
  - Fixed income: 3% mean return, 5% volatility
  - Cash: 2% return, 0% volatility
- **Inflation** — 2% annual
- **Iterations** — Multiple trajectories to compute success probability

The simulation is illustrative — not personalized financial advice.

## Input

```json
{
  "job_id": "<uuid>"
}
```

## Output

Stored in `jobs.retirement_payload`:

```json
{
  "agent": "retirement",
  "analysis": "# Comprehensive Retirement Readiness Analysis\n\n## Assessment of Retirement Readiness\n...",
  "generated_at": "2026-04-28T18:47:09.261793+00:00"
}
```

## Report Structure

The markdown analysis includes:

- **Current Situation Summary** — Age, portfolio value, target retirement age, target income
- **Key Findings** — Success rate, expected portfolio at retirement, gaps
- **Monte Carlo Results** — Probability of sustaining target income
- **Recommendations** — Specific actions to improve retirement readiness
- **Risk Considerations** — Sequence-of-returns risk, longevity risk, inflation risk
- **Disclaimer** — This is illustrative, not financial advice

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

The Retirement agent is one of three specialists invoked by the Planner. The Reporter handles current portfolio analysis, the Charter handles visualizations, and this agent handles forward-looking projections specific to the user's retirement goals.
