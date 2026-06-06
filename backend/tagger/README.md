# Tagger — Instrument Classification Agent

Classifies financial instruments and writes structured allocation data to Agentra's database. Used by the Planner to ensure every position in a portfolio has accurate allocation breakdowns before analysis.

## How It Works

1. Receives a list of instruments (symbol + name) via Lambda invocation
2. For each instrument, calls Bedrock (Claude) with a structured-output prompt
3. The LLM returns asset class, region, and sector percentages summing to 100%
4. Pydantic validates the structure; invalid responses are retried
5. Each result is upserted into the Aurora `instruments` table

```
Planner → invoke Tagger Lambda
              ↓
         Bedrock (Claude 3.7 Sonnet)
              ↓
         Pydantic validation (sum = 100%)
              ↓
         Aurora `instruments` table (upsert)
```

## Input Format

```json
{
  "instruments": [
    {"symbol": "VTI", "name": "Vanguard Total Stock Market ETF"},
    {"symbol": "AAPL", "name": "Apple Inc."}
  ]
}
```

## Output Format

```json
{
  "tagged": 2,
  "updated": ["VTI", "AAPL"],
  "errors": [],
  "classifications": [
    {
      "symbol": "VTI",
      "name": "Vanguard Total Stock Market ETF",
      "type": "etf",
      "current_price": 245.50,
      "asset_class": {"equity": 100},
      "regions": {"north_america": 100},
      "sectors": {"technology": 28, "healthcare": 13, ...}
    }
  ]
}
```

## Environment Variables

| Variable | Description |
|---|---|
| `AURORA_CLUSTER_ARN` | Aurora cluster ARN |
| `AURORA_SECRET_ARN` | Aurora credentials secret ARN |
| `DATABASE_NAME` | Database name (`agentra`) |
| `BEDROCK_MODEL_ID` | Bedrock inference profile ID |
| `BEDROCK_REGION` | Bedrock region |
| `LANGFUSE_PUBLIC_KEY` / `LANGFUSE_SECRET_KEY` / `LANGFUSE_HOST` | Optional LangFuse tracing |
| `OPENAI_API_KEY` | For OpenAI Agents SDK tracing |

## Local Testing

```bash
uv sync
uv run test_simple.py
```

## Deployment

Packaged as part of the multi-agent build. From the `backend/` directory:

```bash
uv run package_layer.py     # build shared deps layer (one-time)
uv run package_handlers.py  # build slim handler zip
cd ../terraform/6_agents
terraform apply
```

## How It Fits Into Agentra

The Tagger runs automatically as a pre-step inside the Planner — when a job is picked up from SQS, the Planner calls the Tagger for any portfolio instruments missing allocation data. This keeps the `instruments` table self-healing as users add new symbols.
