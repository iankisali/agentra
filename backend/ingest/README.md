# Ingest — Document Embedding & Vector Storage

This module contains the Lambda function code for Agentra's document ingestion pipeline. It converts raw text into vector embeddings via SageMaker and stores them in S3 Vectors for semantic search and retrieval.

## What It Does

Two Lambda handlers:

| Handler | Purpose |
|---|---|
| `ingest_s3vectors.py` | Accepts text, generates an embedding via SageMaker, stores the vector + metadata in S3 Vectors |
| `search_s3vectors.py` | Accepts a query, generates an embedding, performs nearest-neighbor search against the vector index |

Supporting files:

| File | Purpose |
|---|---|
| `package.py` | Builds `lambda_function.zip` — bundles handler code + dependencies from `.venv` |
| `main.py` | Placeholder entry point (not used by Lambda) |
| `pyproject.toml` | Python project config managed by `uv` |

## Architecture Diagram

![Ingest Pipeline Architecture](../../assets/ingest.png)

## How It Fits Into Agentra

This is the **data ingestion layer**. Financial text (articles, filings, user inputs) flows through here to become searchable vectors. Downstream, the **Researcher Agent** and **Reporter Agent** query these vectors to retrieve relevant context for analysis and insights.

```
Raw Text → POST /ingest → Lambda → SageMaker Endpoint → Embedding → S3 Vectors
                                                                        ↑
Query Text → POST /search → Lambda → SageMaker Endpoint → Embedding → Nearest-Neighbor Search → Results
```

## Ingest Request Format

```json
{
  "text": "Text content to ingest",
  "metadata": {
    "source": "sec-filing",
    "category": "earnings"
  }
}
```

## Search Request Format

```json
{
  "query": "What were Q4 earnings?",
  "k": 5
}
```

## Environment Variables

| Variable | Description |
|---|---|
| `VECTOR_BUCKET` | S3 Vectors bucket name |
| `SAGEMAKER_ENDPOINT` | Name of the SageMaker embedding endpoint |
| `INDEX_NAME` | Vector index name (default: `financial-research`) |

## Building the Deployment Package

```bash
# Install dependencies
uv sync

# Build lambda_function.zip
python package.py
```

This creates `lambda_function.zip` in the current directory, which Terraform (`terraform/2_ingest`) references during deployment.

## Prerequisites

- Python >= 3.12
- [uv](https://docs.astral.sh/uv/) for dependency management
- A running SageMaker embedding endpoint (deployed via `terraform/1_sagemaker`)
