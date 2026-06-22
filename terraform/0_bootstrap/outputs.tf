output "state_bucket_name" {
  description = "Name of the S3 bucket holding Terraform remote state"
  value       = aws_s3_bucket.state.id
}

output "lock_table_name" {
  description = "Name of the DynamoDB table used for state locking"
  value       = aws_dynamodb_table.locks.name
}

output "backend_config" {
  description = "Backend block to copy into each layer (adjust the key per layer)"
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.state.id}"
        key            = "<LAYER>/terraform.tfstate"
        region         = "${var.aws_region}"
        profile        = "${var.aws_profile}"
        dynamodb_table = "${aws_dynamodb_table.locks.name}"
        encrypt        = true
      }
    }
  EOT
}
