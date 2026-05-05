output "ecr_repository_url" {
  description = "ECR repository URL for the researcher image"
  value       = data.aws_ecr_repository.researcher.repository_url
}

output "task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.ecs_task_execution.arn
}

output "infrastructure_role_arn" {
  description = "ARN of the ECS infrastructure role"
  value       = aws_iam_role.ecs_infrastructure.arn
}

output "task_role_arn" {
  description = "ARN of the ECS task role (Bedrock access)"
  value       = aws_iam_role.ecs_task_role.arn
}

output "service_url" {
  description = "Expected URL of the ECS Express service (after deploy script)"
  value       = "https://agentra-researcher.ecs.${var.aws_region}.on.aws"
}
