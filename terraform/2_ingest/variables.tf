variable "aws_region" {
  description = "AWS region for resources"
  type        = string
}

variable "aws_profile" {
  description = "AWS CLI profile to use for authentication"
  type        = string
  default     = "default"
}

variable "sagemaker_endpoint_name" {
  description = "Name of the SageMaker endpoint from Part 2"
  type        = string
}