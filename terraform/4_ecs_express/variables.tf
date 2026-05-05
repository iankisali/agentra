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
  description = "OpenAI API key for agent tracing"
  type        = string
  sensitive   = true
}

variable "agentra_api_endpoint" {
  description = "Agentra ingest API endpoint"
  type        = string
}

variable "agentra_api_key" {
  description = "Agentra ingest API key"
  type        = string
  sensitive   = true
}
