variable "name" {
  description = "Agent name (e.g. planner, tagger). Used to derive function name, S3 key, and log group."
  type        = string
}

variable "function_name" {
  description = "Full Lambda function name (e.g. agentra-planner)."
  type        = string
}

variable "role_arn" {
  description = "ARN of the IAM role the Lambda assumes."
  type        = string
}

variable "package_bucket" {
  description = "S3 bucket ID where the deployment package is uploaded."
  type        = string
}

variable "source_zip_path" {
  description = "Local path to the agent's deployment zip (relative to the calling module)."
  type        = string
}

variable "handler" {
  description = "Lambda handler entrypoint."
  type        = string
  default     = "lambda_handler.lambda_handler"
}

variable "runtime" {
  description = "Lambda runtime."
  type        = string
  default     = "python3.12"
}

variable "timeout" {
  description = "Function timeout in seconds."
  type        = number
  default     = 300
}

variable "memory_size" {
  description = "Function memory in MB."
  type        = number
  default     = 1024
}

variable "layer_arns" {
  description = "List of Lambda layer ARNs to attach."
  type        = list(string)
  default     = []
}

variable "environment_variables" {
  description = "Map of environment variables for the function."
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "CloudWatch log group retention in days."
  type        = number
  default     = 7
}

variable "tags" {
  description = "Tags applied to all resources created by the module."
  type        = map(string)
  default     = {}
}
