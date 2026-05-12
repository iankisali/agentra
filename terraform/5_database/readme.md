# Database — Aurora Serverless v2 (PostgreSQL)

This Terraform module deploys an Aurora Serverless v2 PostgreSQL cluster for Agentra's persistent data layer — user portfolios, agent job results, financial instruments, and application state.

## What It Deploys

| Resource | Description |
|---|---|
| **Aurora Serverless v2 Cluster** | PostgreSQL 15.12, serverless scaling (0.5–1 ACU), Data API enabled |
| **Aurora Instance** | `db.serverless` instance class attached to the cluster |
| **Secrets Manager Secret** | Auto-generated 32-char password stored securely |
| **DB Subnet Group** | Uses default VPC subnets |
| **Security Group** | Allows PostgreSQL (5432) from within the VPC only |
| **IAM Role + Policy** | Lambda execution role with Data API, Secrets Manager, and CloudWatch access |

## Schema

The database contains five tables:

| Table | Purpose |
|---|---|
| **`users`** | Minimal user data — Clerk handles auth. Stores retirement targets and allocation preferences. |
| **`instruments`** | ETFs, stocks, and funds with current prices and allocation breakdowns (regions, sectors, asset class). Shared reference data. |
| **`accounts`** | User's investment accounts (401k, IRA, Taxable Brokerage) with cash balances. |
| **`positions`** | Holdings in each account — symbol, quantity, as-of date. Unique per (account, symbol). |
| **`jobs`** | Async job tracking for analysis requests. Each agent writes to its own JSONB field. |

### Jobs Table — Agent Output Fields

| Field | Agent | Content |
|---|---|---|
| `report_payload` | Reporter | Markdown portfolio analysis |
| `charts_payload` | Charter | Visualization data (chart configs) |
| `retirement_payload` | Retirement | Long-term projections and scenarios |
| `summary_payload` | Planner | Final summary and metadata |

All data is validated through Pydantic schemas before database insertion. Each agent writes its results to its own dedicated JSONB field, eliminating complex merging logic. Agent execution tracking is handled by LangFuse and CloudWatch Logs, not in the database.

## How It Fits Into Agentra

Aurora is the primary relational database. The agents and API layer interact with it via the **Data API** (HTTP-based, no VPC connectivity required from Lambda/App Runner).

```
Agents / API → Data API (HTTP) → Aurora Serverless v2
                                       ↓
                              Secrets Manager (credentials)
```

## Configuration

| Variable | Description | Default |
|---|---|---|
| `aws_region` | AWS region | — (required) |
| `aws_profile` | AWS CLI profile | `"default"` |
| `min_capacity` | Minimum ACUs (0.5 = smallest, 0 = auto-pause) | `0.5` |
| `max_capacity` | Maximum ACUs | `1` |

## Outputs

| Output | Description |
|---|---|
| `aurora_cluster_arn` | Cluster ARN (used in Data API calls) |
| `aurora_cluster_endpoint` | Writer endpoint (for direct connections) |
| `aurora_secret_arn` | Secrets Manager ARN (used in Data API calls) |
| `database_name` | Database name (`agentra`) |
| `lambda_role_arn` | IAM role ARN for Lambda functions accessing Aurora |
| `data_api_enabled` | Whether the Data API is enabled |

## Usage

```bash
terraform init
terraform plan
terraform apply
```

After deployment, add to your `.env`:

```
AURORA_CLUSTER_ARN=<cluster_arn from output>
AURORA_SECRET_ARN=<secret_arn from output>
```

## Schema Management

All schema and data scripts are in `backend/database/`:

```bash
cd backend/database

# Test Data API connectivity
uv run test_data.py

# Run migrations (creates tables, indexes, triggers)
uv run run_migration.py

# Load 22 ETF instruments with allocation data
uv run seed_data.py

# Full reset: drop → migrate → seed → optional test data
uv run reset_db.py --with-test-data

# Comprehensive verification report
uv run verify_db.py
```

## Cost

- **Minimum (0.5 ACU)**: ~$43/month (always running)
- **With auto-pause (0 ACU min)**: Cluster pauses after 5 min of inactivity, $0 compute while paused
- **Storage**: $0.10/GB-month (billed separately)

To enable auto-pause for development, set `min_capacity = 0` in `terraform.tfvars`.

## Security Notes

- Database credentials are auto-generated and stored in Secrets Manager — never in code or tfvars
- Security group restricts access to VPC CIDR only (no public access)
- Data API access is controlled via IAM (the Lambda role)
- `skip_final_snapshot = true` is set for development — change this for production
