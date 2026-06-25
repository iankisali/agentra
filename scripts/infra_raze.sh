#!/usr/bin/env zsh
#
# infra_raze.sh — Tear down Agentra infrastructure
#
# Destroys each layer in reverse dependency order.
# Automatically includes downstream dependents when targeting a specific layer.
# Requires explicit confirmation unless --auto-approve is passed.
#
# Usage:
#   ./scripts/infra_raze.sh                  # Interactive (all layers except bootstrap)
#   ./scripts/infra_raze.sh --auto-approve   # No prompts
#   ./scripts/infra_raze.sh 5_database       # Destroy 5_database + its dependents (6_agents, 7_frontend)
#   ./scripts/infra_raze.sh --no-deps 5_database  # Destroy only 5_database
#   ./scripts/infra_raze.sh --include-bootstrap    # Also destroy the state bucket
#
# Note: 0_bootstrap is excluded by default (holds all remote state).
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="$ROOT_DIR/terraform"

# ---------------------------------------------------------------------------
# Dependency graph (layer → layers that depend ON it / downstream)
# ---------------------------------------------------------------------------
typeset -A DEPENDENTS
DEPENDENTS[0_bootstrap]="1_sagemaker 2_ingest 3_researcher 5_database 6_agents 7_frontend"
DEPENDENTS[1_sagemaker]="2_ingest"
DEPENDENTS[2_ingest]="3_researcher 6_agents"
DEPENDENTS[3_researcher]=""
DEPENDENTS[5_database]="6_agents 7_frontend"
DEPENDENTS[6_agents]="7_frontend"
DEPENDENTS[7_frontend]=""

# Full ordered list (reverse = destroy order)
ALL_LAYERS_REVERSE=(
  7_frontend
  6_agents
  5_database
  3_researcher
  2_ingest
  1_sagemaker
)

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Ensure AWS profile is set
export AWS_PROFILE="${AWS_PROFILE:-ai}"

auto_approve=false
include_bootstrap=false
no_deps=false
single_layer=""

# Parse args
for arg in "$@"; do
  case "$arg" in
    --auto-approve)      auto_approve=true ;;
    --include-bootstrap) include_bootstrap=true ;;
    --no-deps)           no_deps=true ;;
    *)                   single_layer="$arg" ;;
  esac
done

# Resolve which layers to destroy (target + its downstream dependents)
resolve_layers() {
  local target="$1"
  local resolved=()

  if $no_deps; then
    echo "$target"
    return
  fi

  # Walk the reverse-ordered list, include anything that depends on the target
  # (downstream) plus the target itself — downstream MUST be destroyed first
  local dependents="${DEPENDENTS[$target]}"
  for layer in "${ALL_LAYERS_REVERSE[@]}"; do
    if [[ "$layer" == "$target" ]] || [[ " $dependents " == *" $layer "* ]]; then
      resolved+=("$layer")
    fi
  done

  echo "${resolved[*]}"
}

# Determine layers to destroy
if [[ -n "$single_layer" ]]; then
  if [[ ! -d "$TF_DIR/$single_layer" ]]; then
    echo -e "${RED}Error: Layer '$single_layer' not found in $TF_DIR${NC}"
    exit 1
  fi
  LAYERS=($(resolve_layers "$single_layer"))
else
  LAYERS=("${ALL_LAYERS_REVERSE[@]}")
fi

# Append bootstrap if explicitly requested
if $include_bootstrap && [[ -z "$single_layer" ]]; then
  LAYERS+=(0_bootstrap)
fi

echo -e "${RED}=================================================${NC}"
echo -e "${RED}  Agentra Infrastructure — DESTROY${NC}"
echo -e "${RED}=================================================${NC}"
echo ""
echo -e "AWS Profile: ${GREEN}$AWS_PROFILE${NC}"
echo -e "Layers:      ${YELLOW}${LAYERS[*]}${NC}"
if [[ -n "$single_layer" ]] && ! $no_deps; then
  echo -e "Target:      ${RED}$single_layer${NC} (with downstream dependents)"
fi
echo ""

if ! $auto_approve; then
  echo -e "${RED}WARNING: This will destroy all resources in the listed layers.${NC}"
  echo -e "${RED}         This action is IRREVERSIBLE for stateful resources (databases, S3 data).${NC}"
  echo ""
  echo -n "Type 'destroy' to confirm: "
  read confirmation
  if [[ "$confirmation" != "destroy" ]]; then
    echo -e "${YELLOW}Aborted.${NC}"
    exit 0
  fi
  echo ""
fi

destroy_layer() {
  local layer="$1"
  local layer_dir="$TF_DIR/$layer"

  echo -e "${YELLOW}──────────────────────────────────────────────────${NC}"
  echo -e "${YELLOW}  Destroying: $layer${NC}"
  echo -e "${YELLOW}──────────────────────────────────────────────────${NC}"

  # Init
  echo -e "${BLUE}▸ terraform init${NC}"
  terraform -chdir="$layer_dir" init -input=false -reconfigure > /dev/null 2>&1

  # Plan destroy
  echo -e "${BLUE}▸ terraform plan -destroy${NC}"
  terraform -chdir="$layer_dir" plan -destroy -input=false -out=tfplan-destroy

  # Apply destroy
  echo -e "${RED}▸ terraform apply (destroy)${NC}"
  terraform -chdir="$layer_dir" apply -input=false tfplan-destroy
  rm -f "$layer_dir/tfplan-destroy"

  echo -e "${GREEN}✓ $layer destroyed${NC}"
  echo ""
}

# Run each layer
for layer in "${LAYERS[@]}"; do
  destroy_layer "$layer"
done

echo -e "${GREEN}=================================================${NC}"
echo -e "${GREEN}  All specified layers destroyed.${NC}"
if ! $include_bootstrap && [[ -z "$single_layer" ]]; then
  echo -e "${YELLOW}  Note: 0_bootstrap was preserved (holds remote state).${NC}"
  echo -e "${YELLOW}  Use --include-bootstrap to destroy it too.${NC}"
fi
echo -e "${GREEN}=================================================${NC}"
