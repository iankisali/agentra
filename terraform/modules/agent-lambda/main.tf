terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  package_exists = fileexists(var.source_zip_path)
}

# Deployment package uploaded to S3 (packages > 50MB must use S3)
resource "aws_s3_object" "package" {
  bucket = var.package_bucket
  key    = "${var.name}/${var.name}_lambda.zip"
  source = var.source_zip_path
  # source_hash (not etag) tracks changes reliably even for multipart uploads.
  source_hash = local.package_exists ? filemd5(var.source_zip_path) : null

  tags = var.tags
}

# Agent Lambda function
resource "aws_lambda_function" "this" {
  function_name = var.function_name
  role          = var.role_arn

  s3_bucket        = var.package_bucket
  s3_key           = aws_s3_object.package.key
  source_code_hash = local.package_exists ? filebase64sha256(var.source_zip_path) : null

  handler     = var.handler
  runtime     = var.runtime
  timeout     = var.timeout
  memory_size = var.memory_size
  layers      = var.layer_arns

  environment {
    variables = var.environment_variables
  }

  tags = var.tags
}

# CloudWatch log group for the function
resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}
