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
    key            = "3_researcher/terraform.tfstate"
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

# Data source for current caller identity
data "aws_caller_identity" "current" {}

# ECR repository for the researcher Docker image
resource "aws_ecr_repository" "agentra_researcher" {
  name                 = "agentra-researcher"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = {
    Project = "agentra"
    Part    = "3"
  }
}

# IAM role for App Runner
resource "aws_iam_role" "app_runner_role" {
  name = "agentra-app-runner-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "build.apprunner.amazonaws.com"
        }
      },
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "tasks.apprunner.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Project = "agentra"
    Part    = "3"
  }
}

# Policy for App Runner to access ECR
resource "aws_iam_role_policy_attachment" "app_runner_ecr_access" {
  role       = aws_iam_role.app_runner_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess"
}

# IAM role for App Runner instance (runtime access to AWS services)
resource "aws_iam_role" "app_runner_instance_role" {
  name = "agentra-app-runner-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "tasks.apprunner.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Project = "agentra"
    Part    = "3"
  }
}

# Policy for App Runner instance to access Bedrock
resource "aws_iam_role_policy" "app_runner_instance_bedrock_access" {
  name = "agentra-app-runner-instance-bedrock-policy"
  role = aws_iam_role.app_runner_instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:ListFoundationModels"
        ]
        Resource = "*"
      }
    ]
  })
}

# App Runner service
resource "aws_apprunner_service" "researcher" {
  service_name = "agentra-researcher"

  source_configuration {
    auto_deployments_enabled = false

    # Configure authentication for private ECR repository
    authentication_configuration {
      access_role_arn = aws_iam_role.app_runner_role.arn
    }

    image_repository {
      image_identifier = "${aws_ecr_repository.agentra_researcher.repository_url}:latest"
      image_configuration {
        port = "8000"
        runtime_environment_variables = {
          AWS_DEFAULT_REGION   = var.aws_region
          OPENAI_API_KEY       = var.openai_api_key
          AGENTRA_API_ENDPOINT = var.agentra_api_endpoint
          AGENTRA_API_KEY      = var.agentra_api_key
        }
      }
      image_repository_type = "ECR"
    }
  }

  instance_configuration {
    cpu               = "1 vCPU"
    memory            = "2 GB"
    instance_role_arn = aws_iam_role.app_runner_instance_role.arn
  }

  tags = {
    Project = "agentra"
    Part    = "3"
  }
}

# IAM role for EventBridge
resource "aws_iam_role" "eventbridge_role" {
  count = var.scheduler_enabled ? 1 : 0
  name  = "agentra-eventbridge-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Project = "agentra"
    Part    = "3"
  }
}

# Lambda function for invoking researcher
resource "aws_lambda_function" "scheduler_lambda" {
  count         = var.scheduler_enabled ? 1 : 0
  function_name = "agentra-researcher-scheduler"
  role          = aws_iam_role.lambda_scheduler_role[0].arn

  filename         = "${path.module}/../../backend/scheduler/lambda_function.zip"
  source_code_hash = fileexists("${path.module}/../../backend/scheduler/lambda_function.zip") ? filebase64sha256("${path.module}/../../backend/scheduler/lambda_function.zip") : null

  handler     = "lambda_function.handler"
  runtime     = "python3.12"
  timeout     = 180
  memory_size = 256

  environment {
    variables = {
      APP_RUNNER_URL = aws_apprunner_service.researcher.service_url
    }
  }

  tags = {
    Project = "agentra"
    Part    = "3"
  }
}

# IAM role for scheduler Lambda
resource "aws_iam_role" "lambda_scheduler_role" {
  count = var.scheduler_enabled ? 1 : 0
  name  = "agentra-scheduler-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Project = "agentra"
    Part    = "3"
  }
}

# Lambda basic execution policy
resource "aws_iam_role_policy_attachment" "lambda_scheduler_basic" {
  count      = var.scheduler_enabled ? 1 : 0
  role       = aws_iam_role.lambda_scheduler_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# EventBridge schedule
resource "aws_scheduler_schedule" "research_schedule" {
  count = var.scheduler_enabled ? 1 : 0
  name  = "agentra-research-schedule"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = "rate(2 hours)"

  target {
    arn      = aws_lambda_function.scheduler_lambda[0].arn
    role_arn = aws_iam_role.eventbridge_role[0].arn
  }
}

# Permission for EventBridge to invoke Lambda
resource "aws_lambda_permission" "allow_eventbridge" {
  count         = var.scheduler_enabled ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scheduler_lambda[0].function_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = aws_scheduler_schedule.research_schedule[0].arn
}

# Policy for EventBridge to invoke Lambda
resource "aws_iam_role_policy" "eventbridge_invoke_lambda" {
  count = var.scheduler_enabled ? 1 : 0
  name  = "InvokeLambdaPolicy"
  role  = aws_iam_role.eventbridge_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.scheduler_lambda[0].arn
      }
    ]
  })
}