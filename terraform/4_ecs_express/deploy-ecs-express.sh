#!/bin/bash
# Deploy Agentra Researcher to ECS Express Mode
# Prerequisites: terraform apply (for IAM roles), Docker image in ECR
set -e

AWS_PROFILE="ai"
AWS_REGION="us-east-1"
SERVICE_NAME="agentra-researcher"

echo "Agentra Researcher — ECS Express Mode Deployment"
echo "================================================="

# Get Terraform outputs
echo "Reading Terraform outputs..."
cd "$(dirname "$0")"
ECR_URL=$(terraform output -raw ecr_repository_url)
EXECUTION_ROLE=$(terraform output -raw task_execution_role_arn)
INFRA_ROLE=$(terraform output -raw infrastructure_role_arn)
TASK_ROLE=$(terraform output -raw task_role_arn)

echo "ECR:              $ECR_URL"
echo "Execution Role:   $EXECUTION_ROLE"
echo "Infrastructure:   $INFRA_ROLE"
echo "Task Role:        $TASK_ROLE"

# Load env vars from project root
source ../../.env 2>/dev/null || true

# Check if service already exists
echo ""
echo "Checking for existing service..."
EXISTING=$(aws ecs describe-express-gateway-service \
  --service-name "$SERVICE_NAME" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --query "service.status.statusCode" \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$EXISTING" = "ACTIVE" ]; then
  echo "Service already exists and is ACTIVE. Updating..."
  aws ecs update-express-gateway-service \
    --service-name "$SERVICE_NAME" \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" \
    --primary-container "{\"image\":\"${ECR_URL}:latest\",\"containerPort\":8000,\"environment\":[{\"name\":\"AWS_DEFAULT_REGION\",\"value\":\"${AWS_REGION}\"},{\"name\":\"OPENAI_API_KEY\",\"value\":\"${OPENAI_API_KEY}\"},{\"name\":\"AGENTRA_API_ENDPOINT\",\"value\":\"${AGENTRA_API_ENDPOINT}\"},{\"name\":\"AGENTRA_API_KEY\",\"value\":\"${AGENTRA_API_KEY}\"}]}" \
    --monitor-resources
else
  echo "Creating new ECS Express Mode service..."
  aws ecs create-express-gateway-service \
    --service-name "$SERVICE_NAME" \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" \
    --execution-role-arn "$EXECUTION_ROLE" \
    --infrastructure-role-arn "$INFRA_ROLE" \
    --task-role-arn "$TASK_ROLE" \
    --primary-container "{\"image\":\"${ECR_URL}:latest\",\"containerPort\":8000,\"environment\":[{\"name\":\"AWS_DEFAULT_REGION\",\"value\":\"${AWS_REGION}\"},{\"name\":\"OPENAI_API_KEY\",\"value\":\"${OPENAI_API_KEY}\"},{\"name\":\"AGENTRA_API_ENDPOINT\",\"value\":\"${AGENTRA_API_ENDPOINT}\"},{\"name\":\"AGENTRA_API_KEY\",\"value\":\"${AGENTRA_API_KEY}\"}]}" \
    --cpu 1024 \
    --memory 2048 \
    --health-check-path "/health" \
    --scaling-target '{"minTaskCount":1,"maxTaskCount":3}' \
    --monitor-resources
fi

echo ""
echo "✅ Done! Your service URL will be: https://${SERVICE_NAME}.ecs.${AWS_REGION}.on.aws"
echo "   Test: curl https://${SERVICE_NAME}.ecs.${AWS_REGION}.on.aws/health"
