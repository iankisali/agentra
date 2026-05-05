variable "aws_region" {
  description = "AWS region for resources"
  type        = string
}

variable "aws_profile" {
  description = "AWS CLI profile to use for authentication"
  type        = string
  default     = "default"
}

variable "openai_api_key" {
  description = "OpenAI API key used for agent tracing"
  type        = string
  sensitive   = true
}

variable "agentra_api_endpoint" {
  description = "Agentra API endpoint from Part 3"
  type        = string
}

variable "agentra_api_key" {
  description = "Agentra API key from Part 3"
  type        = string
  sensitive   = true
}

variable "scheduler_enabled" {
  description = "Enable automated research scheduler"
  type        = bool
  default     = false
}