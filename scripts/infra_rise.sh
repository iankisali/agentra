#!/usr/bin/env zsh
#
# infra_rise.sh — Bring up Agentra infrastructure
#
# Runs terraform fmt, init, plan, and apply for each layer in dependency order.
# Automatically includes upstream dependencies when targeting a specific layer.
# Stops immediately if any layer fails.
#
# Usage:
#   ./scripts/infra_rise.sh              # Full deploy (all layers)
#   ./scripts/infra_rise.sh --plan-only  # Format + plan only (no apply)
#   ./scripts/infra_rise.sh 6_agents     # Deploy 6_agents + its dependencies
#   ./scripts/infra_rise.sh --no-deps 6_agents  # Deploy only 6_agents (skip deps)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="$ROOT_DIR/terraform"

# ---------------------------------------------------------------------------
# Dependency graph (layer → layers it depends on)
# ---------------------------------------------------------------------------
typeset -A DEPS
DEPS[0_bootstrap]=""
DEPS[1_sagemaker]="0_bootstrap"
DEPS[2_ingest]="0_bootstrap 1_sagemaker"
DEPS[3_researcher]="0_bootstrap 2_ingest"
DEPS[5_database]="0_bootstrap"
DEPS[6_agents]="0_bootstrap 2_ingest 5_database"
DEPS[7_frontend]="0_bootstrap 5_database 6_agents"

# Full ordered list
ALL_LAYERS=(
  0_bootstrap
  1_sagemaker
  2_ingest
  3_researcher
  5_database
  6_agents
  7_frontend
)

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Ensure AWS profile is set
export AWS_PROFILE="${AWS_PROFILE:-ai}"

plan_only=false
no_deps=false
single_layer=""

# Parse args
for arg in "$@"; do
  case "$arg" in
    --plan-only) plan_only=true ;;
    --no-deps)   no_deps=true ;;
    *)           single_layer="$arg" ;;
  esac
done

# Resolve which layers to deploy
resolve_layers() {
  local target="$1"
  local resolved=()

  if $no_deps; then
    echo "$target"
    return
  fi

  # Walk the full ordered list, include anything that's a dependency of the target
  # or the target itself
  local deps_needed="${DEPS[$target]}"
  for layer in "${ALL_LAYERS[@]}"; do
    if [[ "$layer" == "$target" ]] || [[ " $deps_needed " == *" $layer "* ]]; then
      resolved+=("$layer")
    fi
  done

  echo "${resolved[*]}"
}

# Determine layers to deploy
if [[ -n "$single_layer" ]]; then
  if [[ ! -d "$TF_DIR/$single_layer" ]]; then
    echo -e "${RED}Error: Layer '$single_layer' not found in $TF_DIR${NC}"
    exit 1
  fi
  LAYERS=($(resolve_layers "$single_layer"))
else
  LAYERS=("${ALL_LAYERS[@]}")
fi

echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE}  Agentra Infrastructure — Bring Up${NC}"
echo -e "${BLUE}=================================================${NC}"
echo ""
echo -e "AWS Profile: ${GREEN}$AWS_PROFILE${NC}"
echo -e "Mode:        ${GREEN}$(if $plan_only; then echo 'Plan Only'; else echo 'Full Deploy'; fi)${NC}"
echo -e "Layers:      ${GREEN}${LAYERS[*]}${NC}"
if [[ -n "$single_layer" ]] && ! $no_deps; then
  echo -e "Target:      ${YELLOW}$single_layer${NC} (with dependencies)"
fi
echo ""

deploy_layer() {
  local layer="$1"
  local layer_dir="$TF_DIR/$layer"

  echo -e "${YELLOW}──────────────────────────────────────────────────${NC}"
  echo -e "${YELLOW}  Layer: $layer${NC}"
  echo -e "${YELLOW}──────────────────────────────────────────────────${NC}"

  # Init
  echo -e "${BLUE}▸ terraform init${NC}"
  terraform -chdir="$layer_dir" init -input=false -reconfigure > /dev/null 2>&1

  # Plan
  echo -e "${BLUE}▸ terraform plan${NC}"
  terraform -chdir="$layer_dir" plan -input=false -out=tfplan

  if $plan_only; then
    echo -e "${GREEN}✓ Plan complete for $layer (--plan-only, skipping apply)${NC}"
    rm -f "$layer_dir/tfplan"
    echo ""
    return
  fi

  # Pre-deploy: for researcher, create ECR first and push the image before full apply
  if [[ "$layer" == "3_researcher" ]] && ! $plan_only; then
    echo -e "${BLUE}▸ terraform apply (ECR only — image must exist before App Runner)${NC}"
    terraform -chdir="$layer_dir" apply -input=false -target=aws_ecr_repository.agentra_researcher tfplan 2>/dev/null || \
      terraform -chdir="$layer_dir" apply -input=false -target=aws_ecr_repository.agentra_researcher -auto-approve
    rm -f "$layer_dir/tfplan"

    echo ""
    echo -e "${BLUE}▸ Building and pushing Researcher Docker image to ECR...${NC}"
    local researcher_dir="$ROOT_DIR/backend/researcher"
    local aws_region="${AWS_DEFAULT_REGION:-us-east-1}"
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local ecr_url="${account_id}.dkr.ecr.${aws_region}.amazonaws.com/agentra-researcher"

    # ECR login
    echo -e "${BLUE}  → ECR login${NC}"
    aws ecr get-login-password --region "$aws_region" | \
      docker login --username AWS --password-stdin "${account_id}.dkr.ecr.${aws_region}.amazonaws.com"

    # Build image
    echo -e "${BLUE}  → Building Docker image (linux/amd64)${NC}"
    docker build --platform linux/amd64 -t agentra-researcher:latest "$researcher_dir"

    # Tag and push
    echo -e "${BLUE}  → Pushing to ECR${NC}"
    docker tag agentra-researcher:latest "${ecr_url}:latest"
    docker push "${ecr_url}:latest"

    echo -e "${GREEN}✓ Researcher image pushed to ECR${NC}"
    echo ""

    # Now do the full apply (App Runner will find the image)
    echo -e "${BLUE}▸ terraform plan (full)${NC}"
    terraform -chdir="$layer_dir" plan -input=false -out=tfplan
    echo -e "${BLUE}▸ terraform apply (full)${NC}"
    terraform -chdir="$layer_dir" apply -input=false tfplan
    rm -f "$layer_dir/tfplan"
  else
    # Apply
    echo -e "${BLUE}▸ terraform apply${NC}"
    terraform -chdir="$layer_dir" apply -input=false tfplan
    rm -f "$layer_dir/tfplan"
  fi

  # Post-deploy: run database migration and seed if this is the database layer
  if [[ "$layer" == "5_database" ]]; then
    echo ""
    echo -e "${BLUE}▸ Running database migration and seed...${NC}"
    local db_dir="$ROOT_DIR/backend/database"

    # Capture the new ARNs from terraform output
    echo -e "${BLUE}  → Reading terraform outputs...${NC}"
    local cluster_arn=$(terraform -chdir="$layer_dir" output -raw aurora_cluster_arn)
    local secret_arn=$(terraform -chdir="$layer_dir" output -raw aurora_secret_arn)
    local db_name=$(terraform -chdir="$layer_dir" output -raw database_name)

    echo -e "${GREEN}  Cluster: $cluster_arn${NC}"
    echo -e "${GREEN}  Secret:  $secret_arn${NC}"
    echo -e "${GREEN}  DB Name: $db_name${NC}"

    # Export so the Python scripts pick them up (overrides .env values)
    export AURORA_CLUSTER_ARN="$cluster_arn"
    export AURORA_SECRET_ARN="$secret_arn"
    export AURORA_DATABASE="$db_name"

    # Update .env BEFORE running scripts (dotenv load_dotenv(override=True) reads from it)
    echo -e "${BLUE}  → Updating .env with new ARNs...${NC}"
    local env_file="$ROOT_DIR/.env"
    if [[ -f "$env_file" ]]; then
      sed -i '' "s|^AURORA_CLUSTER_ARN=.*|AURORA_CLUSTER_ARN=$cluster_arn|" "$env_file"
      sed -i '' "s|^AURORA_SECRET_ARN=.*|AURORA_SECRET_ARN=$secret_arn|" "$env_file"
      # Also handle commented-out lines
      sed -i '' "s|^#AURORA_SECRET_ARN=.*||" "$env_file"
    fi

    echo -e "${BLUE}  → uv sync${NC}"
    (cd "$db_dir" && uv sync --quiet)

    echo -e "${BLUE}  → run_migration.py${NC}"
    (cd "$db_dir" && uv run run_migration.py)

    echo -e "${BLUE}  → seed_data.py${NC}"
    (cd "$db_dir" && uv run seed_data.py)

    # echo -e "${BLUE}  → reset_db.py --with-test-data${NC}"
    # (cd "$db_dir" && uv run reset_db.py --with-test-data)

    echo -e "${GREEN}✓ Database migrated, seeded, and .env updated${NC}"
  fi

  # Post-deploy: build and upload frontend if this is the frontend layer
  if [[ "$layer" == "7_frontend" ]]; then
    echo ""
    echo -e "${BLUE}▸ Building and deploying Next.js frontend...${NC}"
    local frontend_dir="$ROOT_DIR/frontend"
    local aws_region="${AWS_DEFAULT_REGION:-us-east-1}"

    # Get CloudFront domain from terraform output
    local cloudfront_url=$(terraform -chdir="$layer_dir" output -raw cloudfront_url 2>/dev/null || echo "")
    local cloudfront_domain=$(echo "$cloudfront_url" | sed 's|https://||')
    local distribution_id=$(aws cloudfront list-distributions \
      --query "DistributionList.Items[?Comment=='Agentra Financial Advisor Frontend'].Id" \
      --output text 2>/dev/null || echo "")
    local bucket_name="agentra-frontend-$(aws sts get-caller-identity --query Account --output text)"

    echo -e "${GREEN}  CloudFront: $cloudfront_url${NC}"
    echo -e "${GREEN}  Bucket:     $bucket_name${NC}"

    # Build frontend with production API URL (CloudFront proxies /api/* to API Gateway)
    echo -e "${BLUE}  → npm install${NC}"
    (cd "$frontend_dir" && npm install --silent)

    echo -e "${BLUE}  → npm run build (NEXT_PUBLIC_API_URL=$cloudfront_url)${NC}"
    (cd "$frontend_dir" && NEXT_PUBLIC_API_URL="$cloudfront_url" npm run build)

    # Upload to S3
    echo -e "${BLUE}  → Syncing to S3${NC}"
    aws s3 sync "$frontend_dir/out/" "s3://$bucket_name/" --delete

    # Invalidate CloudFront cache
    if [[ -n "$distribution_id" ]]; then
      echo -e "${BLUE}  → Invalidating CloudFront cache${NC}"
      aws cloudfront create-invalidation --distribution-id "$distribution_id" --paths "/*" > /dev/null 2>&1
      echo -e "${GREEN}✓ CloudFront invalidation initiated${NC}"
    fi

    echo -e "${GREEN}✓ Frontend built and deployed to $cloudfront_url${NC}"
  fi

  echo -e "${GREEN}✓ $layer deployed successfully${NC}"
  echo ""
}

# Run each layer
for layer in "${LAYERS[@]}"; do
  deploy_layer "$layer"
done

echo -e "${GREEN}=================================================${NC}"
if $plan_only; then
  echo -e "${GREEN}  All layers planned successfully!${NC}"
else
  echo -e "${GREEN}  All layers deployed successfully!${NC}"
fi
echo -e "${GREEN}=================================================${NC}"
