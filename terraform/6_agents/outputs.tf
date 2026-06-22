output "sqs_queue_url" {
  description = "URL of the SQS queue for job submission"
  value       = aws_sqs_queue.analysis_jobs.url
}

output "sqs_queue_arn" {
  description = "ARN of the SQS queue"
  value       = aws_sqs_queue.analysis_jobs.arn
}

output "lambda_functions" {
  description = "Names of deployed Lambda functions"
  value       = { for k, m in module.agents : k => m.function_name }
}

output "lambda_arns" {
  description = "ARNs of deployed Lambda functions"
  value       = { for k, m in module.agents : k => m.function_arn }
}

output "setup_instructions" {
  description = "Instructions for testing the agents"
  value = <<-EOT
    
    Agent infrastructure deployed successfully!
    
    Lambda Functions:
    %{for name, m in module.agents~}
    - ${m.function_name}
    %{endfor~}
    
    SQS Queue: ${aws_sqs_queue.analysis_jobs.name}
    
    Aurora Cluster ARN (from remote state): ${local.aurora_cluster_arn}
    Aurora Secret ARN  (from remote state): ${local.aurora_secret_arn}
    Vector Bucket      (from remote state): ${local.vector_bucket}
    
    To test the system:
    1. Package and deploy each agent's code:
       cd backend/<agent> && uv run package_docker.py --deploy
    
    2. Run the full integration test:
       cd backend/planner && uv run run_full_test.py
    
    Bedrock Model: ${var.bedrock_model_id}
    Region: ${var.bedrock_region}
  EOT
}
