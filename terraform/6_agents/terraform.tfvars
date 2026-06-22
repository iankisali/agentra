# Part 6: Agent Orchestra Configuration

aws_region  = "us-east-1"
aws_profile = "ai"

# Bedrock model configuration
bedrock_model_id = "us.amazon.nova-pro-v1:0"
bedrock_region   = "us-east-1"

# SageMaker endpoint name from Part 1
sagemaker_endpoint = "agentra-embedding-endpoint"

# Polygon.io plan type (free or paid)
polygon_plan = "free"

# NOTE: aurora_cluster_arn, aurora_secret_arn, and vector_bucket are now
# automatically read from 5_database and 2_ingest remote state.
# No more manual ARN copy/paste!

# NOTE: Secrets (polygon_api_key, openai_api_key, langfuse keys) are in
# secrets.auto.tfvars which is gitignored. See secrets.auto.tfvars.example.
