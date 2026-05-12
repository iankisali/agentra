# Database — Schema, Migrations & Tooling

This module contains the database schema, migration scripts, seed data, and verification tools for Agentra's Aurora Serverless v2 PostgreSQL database.

## Schema Overview

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│    users     │────▶│   accounts   │────▶│  positions   │
│ (Clerk auth) │     │ (401k, IRA)  │     │ (holdings)   │
└──────────────┘     └──────────────┘     └──────┬───────┘
       │                                         │
       │              ┌──────────────┐           │
       └─────────────▶│     jobs     │           │
                      │ (agent runs) │     ┌─────▼───────┐
                      └──────────────┘     │ instruments │
                                           │ (ETFs/funds)│
                                           └─────────────┘
```

### Table Descriptions

| Table | Primary Key | Purpose |
|---|---|---|
| **`users`** | `clerk_user_id` (VARCHAR) | Minimal user data — Clerk handles auth. Stores retirement targets and allocation preferences (JSONB). |
| **`instruments`** | `symbol` (VARCHAR) | ETFs, stocks, and funds with current prices and allocation breakdowns by region, sector, and asset class (JSONB). Shared reference data. |
| **`accounts`** | `id` (UUID) | User's investment accounts (401k, IRA, Taxable). Tracks cash balance and interest rate. |
| **`positions`** | `id` (UUID) | Holdings in each account. Unique constraint on (account_id, symbol). |
| **`jobs`** | `id` (UUID) | Async job tracking for analysis requests. Each agent writes to its own JSONB field. |

### Jobs Table — Agent Output Fields

Each agent writes its results to a dedicated JSONB column, eliminating merge conflicts:

| Column | Agent | Content |
|---|---|---|
| `report_payload` | Reporter | Markdown portfolio analysis |
| `charts_payload` | Charter | Visualization data and chart configs |
| `retirement_payload` | Retirement | Long-term projections and scenarios |
| `summary_payload` | Planner | Final summary and orchestration metadata |

Agent execution tracking (traces, latency, token usage) is handled by LangFuse and CloudWatch Logs — not stored in the database.

## Key Files

| File | Purpose |
|---|---|
| `run_migration.py` | Creates all tables, indexes, triggers, and the `uuid-ossp` extension |
| `seed_data.py` | Loads 22 ETF instruments with full allocation data (regions, sectors, asset class) |
| `reset_db.py` | Full reset: drop all → migrate → seed → optionally create test user with portfolio |
| `test_data.py` | Tests Aurora Data API connectivity and verifies cluster configuration |
| `verify_db.py` | Comprehensive verification: table counts, allocation validation, indexes, triggers |

## Usage

All scripts use the Data API (no direct PostgreSQL connection needed). Set these in your `.env`:

```
AURORA_CLUSTER_ARN=arn:aws:rds:us-east-1:123456789:cluster:agentra-aurora-cluster
AURORA_SECRET_ARN=arn:aws:secretsmanager:us-east-1:123456789:secret:agentra-aurora-credentials-xxxx
```

### First-time setup

```bash
# 0. Install dependencies (required once)
uv sync

# 1. Test connectivity
uv run test_data.py

# 2. Create schema
uv run run_migration.py

# 3. Load instruments
uv run seed_data.py

# 4. Verify everything
uv run verify_db.py
```

### Full reset (development)

```bash
# Drop everything, recreate, seed, and add test user
uv run reset_db.py --with-test-data
```

### Test data

The `--with-test-data` flag creates:
- User: `test_user_001`
- 3 accounts: 401(k), Roth IRA, Taxable Brokerage
- 5 positions in the 401(k): SPY, QQQ, BND, VEA, GLD

## Seed Instruments

22 ETFs covering:
- **Core US Equity**: SPY, QQQ, IWM
- **International**: VEA, VWO, EFA
- **Fixed Income**: AGG, BND, TLT, HYG
- **Sectors**: XLK, XLV, XLF, XLE
- **Real Estate**: VNQ
- **Commodities**: GLD, SLV
- **Mixed/Balanced**: AOR, AOA
- **Growth/Value/Dividend**: VUG, VTV, VIG

Each instrument includes allocation percentages that sum to 100% for regions, sectors, and asset class — validated by Pydantic before insertion.

## Data Validation

All data passes through Pydantic schemas (`src/schemas.py`) before database insertion:
- `UserCreate` — validates retirement targets and allocation preferences
- `AccountCreate` — validates cash balance and interest rate
- `PositionCreate` — validates account reference and quantity
- `InstrumentCreate` — validates allocation percentages sum to 100%

## How It Fits Into Agentra

This is the data foundation. The API layer reads/writes user data and job results. Agents write their analysis outputs to the `jobs` table. The frontend reads job results to display insights.

```
Frontend → API → Data API → Aurora (read user data, job results)
Agents → Data API → Aurora (write analysis to jobs table)
```
