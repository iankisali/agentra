terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "agentra-tfstate-773872230003"
    key            = "6_agents/terraform.tfstate"
    region         = "us-east-1"
    profile        = "ai"
    dynamodb_table = "agentra-tfstate-locks"
    encrypt        = true
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

# ---------------------------------------------------------------------------
# Remote State References — eliminates manual ARN copy/paste between layers
# ---------------------------------------------------------------------------

data "terraform_remote_state" "database" {
  backend = "s3"
  config = {
    bucket  = "agentra-tfstate-773872230003"
    key     = "5_database/terraform.tfstate"
    region  = "us-east-1"
    profile = "ai"
  }
}

data "terraform_remote_state" "ingest" {
  backend = "s3"
  config = {
    bucket  = "agentra-tfstate-773872230003"
    key     = "2_ingest/terraform.tfstate"
    region  = "us-east-1"
    profile = "ai"
  }
}

# ---------------------------------------------------------------------------
# Locals — single source of truth for values derived from remote state
# ---------------------------------------------------------------------------

locals {
  aurora_cluster_arn = data.terraform_remote_state.database.outputs.aurora_cluster_arn
  aurora_secret_arn  = data.terraform_remote_state.database.outputs.aurora_secret_arn
  database_name      = data.terraform_remote_state.database.outputs.database_name
  vector_bucket      = data.terraform_remote_state.ingest.outputs.vector_bucket_name

  common_tags = {
    Project   = "agentra"
    Part      = "6"
    ManagedBy = "terraform"
  }

  # Agent configuration map — defines per-agent overrides
  # Planner gets more memory/timeout as orchestrator; others share defaults
  agents = {
    planner = {
      timeout     = 900  # 15 minutes — orchestrates all other agents
      memory_size = 2048 # 2 GB
      tag_name    = "orchestrator"
      extra_env = {
        VECTOR_BUCKET      = local.vector_bucket
        SAGEMAKER_ENDPOINT = var.sagemaker_endpoint
        POLYGON_API_KEY    = var.polygon_api_key
        POLYGON_PLAN       = var.polygon_plan
      }
    }
    tagger = {
      timeout     = 300
      memory_size = 1024
      tag_name    = "tagger"
      extra_env   = {}
    }
    reporter = {
      timeout     = 300
      memory_size = 1024
      tag_name    = "reporter"
      extra_env = {
        SAGEMAKER_ENDPOINT = var.sagemaker_endpoint
      }
    }
    charter = {
      timeout     = 300
      memory_size = 1024
      tag_name    = "charter"
      extra_env   = {}
    }
    retirement = {
      timeout     = 300
      memory_size = 1024
      tag_name    = "retirement"
      extra_env   = {}
    }
  }

  # Environment variables shared by ALL agents
  common_env = {
    AURORA_CLUSTER_ARN  = local.aurora_cluster_arn
    AURORA_SECRET_ARN   = local.aurora_secret_arn
    DATABASE_NAME       = local.database_name
    BEDROCK_MODEL_ID    = var.bedrock_model_id
    BEDROCK_REGION      = var.bedrock_region
    DEFAULT_AWS_REGION  = var.aws_region
    LANGFUSE_PUBLIC_KEY = var.langfuse_public_key
    LANGFUSE_SECRET_KEY = var.langfuse_secret_key
    LANGFUSE_HOST       = var.langfuse_host
    OPENAI_API_KEY      = var.openai_api_key
  }
}

# ---------------------------------------------------------------------------
# Data Sources
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# SQS — Asynchronous job processing
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "analysis_jobs" {
  name                       = "agentra-analysis-jobs"
  delay_seconds              = 0
  max_message_size           = 262144
  message_retention_seconds  = 86400 # 1 day
  receive_wait_time_seconds  = 10    # Long polling
  visibility_timeout_seconds = 910   # 15 min + 10s buffer (matches Planner timeout)

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.analysis_jobs_dlq.arn
    maxReceiveCount     = 3
  })

  tags = local.common_tags
}

resource "aws_sqs_queue" "analysis_jobs_dlq" {
  name = "agentra-analysis-jobs-dlq"
  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# IAM — Shared role and policy for all agent Lambdas
# ---------------------------------------------------------------------------

resource "aws_iam_role" "lambda_agents_role" {
  name = "agentra-lambda-agents-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "lambda_agents_policy" {
  name = "agentra-lambda-agents-policy"
  role = aws_iam_role.lambda_agents_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = aws_sqs_queue.analysis_jobs.arn
      },
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:agentra-*"
      },
      {
        Effect = "Allow"
        Action = [
          "rds-data:ExecuteStatement",
          "rds-data:BatchExecuteStatement",
          "rds-data:BeginTransaction",
          "rds-data:CommitTransaction",
          "rds-data:RollbackTransaction"
        ]
        Resource = local.aurora_cluster_arn
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = local.aurora_secret_arn
      },
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::${local.vector_bucket}",
          "arn:aws:s3:::${local.vector_bucket}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["s3vectors:QueryVectors", "s3vectors:GetVectors"]
        Resource = "arn:aws:s3vectors:${var.aws_region}:${data.aws_caller_identity.current.account_id}:bucket/${local.vector_bucket}/index/*"
      },
      {
        Effect   = "Allow"
        Action   = ["sagemaker:InvokeEndpoint"]
        Resource = "arn:aws:sagemaker:${var.aws_region}:${data.aws_caller_identity.current.account_id}:endpoint/${var.sagemaker_endpoint}"
      },
      {
        Effect = "Allow"
        Action = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
        Resource = [
          "arn:aws:bedrock:*::foundation-model/*",
          "arn:aws:bedrock:*:*:inference-profile/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_agents_basic" {
  role       = aws_iam_role.lambda_agents_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ---------------------------------------------------------------------------
# S3 — Lambda deployment packages
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "lambda_packages" {
  bucket = "agentra-lambda-packages-${data.aws_caller_identity.current.account_id}"
  tags   = local.common_tags
}

# Shared dependencies layer
resource "aws_s3_object" "shared_layer" {
  bucket = aws_s3_bucket.lambda_packages.id
  key    = "layers/shared_layer.zip"
  source = "${path.module}/../../backend/shared_layer.zip"
  # Use source_hash (not etag): the layer is large enough to be uploaded as a
  # multipart object, whose S3 ETag is not a plain MD5 — using etag here causes
  # a perpetual diff. source_hash tracks local changes without that issue.
  source_hash = fileexists("${path.module}/../../backend/shared_layer.zip") ? filemd5("${path.module}/../../backend/shared_layer.zip") : null
}

resource "aws_lambda_layer_version" "shared_deps" {
  layer_name          = "agentra-shared-deps"
  description         = "Shared Python dependencies for all Agentra agents"
  s3_bucket           = aws_s3_bucket.lambda_packages.id
  s3_key              = aws_s3_object.shared_layer.key
  source_code_hash    = fileexists("${path.module}/../../backend/shared_layer.zip") ? filebase64sha256("${path.module}/../../backend/shared_layer.zip") : null
  compatible_runtimes = ["python3.12"]

  depends_on = [aws_s3_object.shared_layer]
}

# Per-agent deployment packages
# (now created inside the agent-lambda module)

# ---------------------------------------------------------------------------
# Lambda Functions — all 5 agents via the reusable agent-lambda module
# ---------------------------------------------------------------------------

module "agents" {
  source   = "../modules/agent-lambda"
  for_each = local.agents

  name            = each.key
  function_name   = "agentra-${each.key}"
  role_arn        = aws_iam_role.lambda_agents_role.arn
  package_bucket  = aws_s3_bucket.lambda_packages.id
  source_zip_path = "${path.module}/../../backend/${each.key}/${each.key}_lambda.zip"

  timeout     = each.value.timeout
  memory_size = each.value.memory_size
  layer_arns  = [aws_lambda_layer_version.shared_deps.arn]

  environment_variables = merge(local.common_env, each.value.extra_env)

  log_retention_days = 7

  tags = merge(local.common_tags, { Agent = each.value.tag_name })
}

# ---------------------------------------------------------------------------
# State migration — map old in-layer resource addresses to the new module
# addresses so Terraform updates in place instead of destroy/recreate.
# for_each is on the module, so the key lives on the module address.
# ---------------------------------------------------------------------------

moved {
  from = aws_lambda_function.agents["planner"]
  to   = module.agents["planner"].aws_lambda_function.this
}
moved {
  from = aws_lambda_function.agents["tagger"]
  to   = module.agents["tagger"].aws_lambda_function.this
}
moved {
  from = aws_lambda_function.agents["reporter"]
  to   = module.agents["reporter"].aws_lambda_function.this
}
moved {
  from = aws_lambda_function.agents["charter"]
  to   = module.agents["charter"].aws_lambda_function.this
}
moved {
  from = aws_lambda_function.agents["retirement"]
  to   = module.agents["retirement"].aws_lambda_function.this
}

moved {
  from = aws_s3_object.lambda_packages["planner"]
  to   = module.agents["planner"].aws_s3_object.package
}
moved {
  from = aws_s3_object.lambda_packages["tagger"]
  to   = module.agents["tagger"].aws_s3_object.package
}
moved {
  from = aws_s3_object.lambda_packages["reporter"]
  to   = module.agents["reporter"].aws_s3_object.package
}
moved {
  from = aws_s3_object.lambda_packages["charter"]
  to   = module.agents["charter"].aws_s3_object.package
}
moved {
  from = aws_s3_object.lambda_packages["retirement"]
  to   = module.agents["retirement"].aws_s3_object.package
}

moved {
  from = aws_cloudwatch_log_group.agent_logs["planner"]
  to   = module.agents["planner"].aws_cloudwatch_log_group.this
}
moved {
  from = aws_cloudwatch_log_group.agent_logs["tagger"]
  to   = module.agents["tagger"].aws_cloudwatch_log_group.this
}
moved {
  from = aws_cloudwatch_log_group.agent_logs["reporter"]
  to   = module.agents["reporter"].aws_cloudwatch_log_group.this
}
moved {
  from = aws_cloudwatch_log_group.agent_logs["charter"]
  to   = module.agents["charter"].aws_cloudwatch_log_group.this
}
moved {
  from = aws_cloudwatch_log_group.agent_logs["retirement"]
  to   = module.agents["retirement"].aws_cloudwatch_log_group.this
}

# ---------------------------------------------------------------------------
# SQS Trigger — Planner is the entry point
# ---------------------------------------------------------------------------

resource "aws_lambda_event_source_mapping" "planner_sqs" {
  event_source_arn = aws_sqs_queue.analysis_jobs.arn
  function_name    = module.agents["planner"].function_arn
  batch_size       = 1
}

# ---------------------------------------------------------------------------
# CloudWatch Log Groups are created inside the agent-lambda module.
# ---------------------------------------------------------------------------
