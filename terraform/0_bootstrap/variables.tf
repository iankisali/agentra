variable "aws_region" {
  description = "AWS region for the state bucket and lock table"
  type        = string
}

variable "aws_profile" {
  description = "AWS CLI profile to use for authentication"
  type        = string
  default     = "default"
}
