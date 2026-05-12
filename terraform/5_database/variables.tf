variable "aws_region" {
  description = "AWS region for resources"
  type        = string
}

variable "aws_profile" {
  description = "AWS CLI profile to use for authentication"
  type        = string
  default     = "default"
}

variable "min_capacity" {
  description = "Minimum capacity for Aurora Serverless v2 (in ACUs)"
  type        = number
  default     = 0.5
}

variable "max_capacity" {
  description = "Maximum capacity for Aurora Serverless v2 (in ACUs)"
  type        = number
  default     = 1
}