# Scripts

Automation scripts for deploying, managing, and tearing down the Agentra platform.

---

## Infrastructure Scripts

### `infra_rise.sh` — Deploy Infrastructure

Runs `terraform init`, `plan`, and `apply` for each layer in dependency order.

```bash
# Deploy all layers (full stack)
./scripts/infra_rise.sh

# Plan only (no apply) — useful for reviewing changes
./scripts/infra_rise.sh --plan-only

# Deploy a single layer + its upstream dependencies
./scripts/infra_rise.sh 6_agents
# → Deploys: 0_bootstrap → 2_ingest → 5_database → 6_agents

# Deploy a single layer without dependencies
./scripts/infra_rise.sh --no-deps 6_agents
```

**Dependency resolution (up):** When targeting a layer, the script automatically
deploys its upstream dependencies first. For example, `6_agents` depends on
`0_bootstrap`, `2_ingest`, and `5_database` — all will be deployed in order.

### `infra_raze.sh` — Destroy Infrastructure

Destroys each layer in reverse dependency order. Requires confirmation.

```bash
# Destroy all layers (except 0_bootstrap)
./scripts/infra_raze.sh

# Destroy without prompts (CI use)
./scripts/infra_raze.sh --auto-approve

# Destroy a single layer + its downstream dependents
./scripts/infra_raze.sh 5_database
# → Destroys: 7_frontend → 6_agents → 5_database

# Destroy only a specific layer (skip dependents)
./scripts/infra_raze.sh --no-deps 5_database

# Also destroy the state bucket (after everything else)
./scripts/infra_raze.sh --include-bootstrap
```

**Dependency resolution (destroy):** When targeting a layer, the script
automatically destroys its downstream dependents first. For example, destroying
`5_database` will first destroy `7_frontend` and `6_agents` (which depend on it).

**Safety:** `0_bootstrap` is never destroyed unless `--include-bootstrap` is
explicitly passed. It holds the S3 remote state for all other layers.

---

## Dependency Graph

```
0_bootstrap
├── 1_sagemaker
│   └── 2_ingest
│       └── 3_researcher
├── 5_database
│   ├── 6_agents ← also depends on 2_ingest
│   │   └── 7_frontend
│   └── 7_frontend
└── (all layers depend on 0_bootstrap for remote state)
```

---

## Deployment Scripts

### `deploy.py` — Full Application Deploy

Packages Lambda functions, deploys Terraform, builds the Next.js frontend,
uploads to S3, and invalidates CloudFront. This is the higher-level "ship it"
script that wraps infrastructure + application deployment.

```bash
AWS_PROFILE=ai uv run deploy.py
```

### `run_local.py` — Local Development

Starts the application locally for development.

```bash
uv run run_local.py
```

---

## Prerequisites

- `AWS_PROFILE` set (defaults to `ai` if not specified)
- Terraform >= 1.5
- Docker running (for Lambda packaging)
- `uv` installed (for Python scripts)
- `secrets.auto.tfvars` files in place for layers that need them

---

## Environment Variable

| Variable | Default | Purpose |
|---|---|---|
| `AWS_PROFILE` | `ai` | AWS CLI profile used for all Terraform operations |

---

## Flags Reference

| Flag | Script | Effect |
|---|---|---|
| `--plan-only` | `infra_rise.sh` | Run plan without applying |
| `--no-deps` | Both | Skip dependency/dependent resolution |
| `--auto-approve` | `infra_raze.sh` | Skip confirmation prompt |
| `--include-bootstrap` | `infra_raze.sh` | Also destroy the state bucket |
