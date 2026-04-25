# SageMaker Embedding Endpoint

This Terraform module provisions a **serverless SageMaker endpoint** that hosts a HuggingFace embedding model. The endpoint converts raw text into embedding vectors, which are stored in Agentra's vector database for semantic search and retrieval.

## What It Deploys

| Resource | Description |
|---|---|
| `aws_iam_role` | IAM role with SageMaker full access for model execution |
| `aws_sagemaker_model` | HuggingFace model container (`sentence-transformers/all-MiniLM-L6-v2` by default) |
| `aws_sagemaker_endpoint_configuration` | Serverless inference config (3 GB memory, max 2 concurrent invocations) |
| `aws_sagemaker_endpoint` | The live inference endpoint |
| `time_sleep` | 15-second delay to allow IAM role propagation before endpoint creation |

## How It Fits Into Agentra

The embedding endpoint is a foundational piece of the data pipeline. During ingestion, raw financial text (articles, filings, user inputs) is sent to this endpoint to produce vector embeddings. These embeddings power the **Researcher Agent's** semantic search and the **Reporter Agent's** context retrieval.

```
Raw Text → SageMaker Endpoint → Embedding Vector → Vector Database
```

## Prerequisites

- Terraform >= 1.5
- AWS CLI configured with a named profile that has permissions to manage IAM and SageMaker
- The SageMaker container image must be accessible in the target region (default: `us-east-1`)

## Configuration

All variables are defined in `variables.tf`. Set values in `terraform.tfvars`:

| Variable | Description | Default |
|---|---|---|
| `aws_region` | AWS region for all resources | — (required) |
| `aws_profile` | AWS CLI profile for authentication | `"default"` |
| `sagemaker_image_uri` | ECR URI for the HuggingFace inference container | HF PyTorch CPU image (us-east-1) |
| `embedding_model_name` | HuggingFace model ID | `sentence-transformers/all-MiniLM-L6-v2` |

Example `terraform.tfvars`:

```hcl
aws_region  = "us-east-1"
aws_profile = "agentra-dev"
```

## Outputs

| Output | Description |
|---|---|
| `aws_iam_role` | Name of the SageMaker IAM role |
| `sagemaker_endpoint_name` | Name of the deployed SageMaker endpoint |
| `sagemaker_endpoint_arn` | ARN of the deployed SageMaker endpoint |

## Usage

```bash
# Initialize
terraform init

# Preview changes
terraform plan

# Deploy
terraform apply

# Tear down
terraform destroy
```

## References

- [AWS SageMaker ECR Image URIs (us-east-1)](https://docs.aws.amazon.com/sagemaker/latest/dg-ecr-paths/ecr-us-east-1.html#huggingface-us-east-1)
- [HuggingFace Inference Endpoints](https://huggingface.co/docs/inference-endpoints)
- [SageMaker Serverless Inference](https://docs.aws.amazon.com/sagemaker/latest/dg/serverless-endpoints.html)
