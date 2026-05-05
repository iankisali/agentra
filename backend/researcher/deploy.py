#!/usr/bin/env python3
"""
Deploy researcher service to AWS App Runner.
Builds Docker image, pushes to ECR, and updates the App Runner service.
"""

import subprocess
import sys
import os
import json
import time
from pathlib import Path
from dotenv import load_dotenv

# Load environment variables from project root .env
env_path = Path(__file__).parent.parent.parent / ".env"
load_dotenv(env_path, override=True)

# Configuration from environment
AWS_PROFILE = os.getenv("AWS_PROFILE", "default")
AWS_REGION = os.getenv("AWS_DEFAULT_REGION", "us-east-1")
ECR_REPOSITORY = "agentra-researcher"
SERVICE_NAME = "agentra-researcher"


def run_command(cmd, capture_output=False):
    """Run a command and handle errors."""
    try:
        result = subprocess.run(cmd, capture_output=capture_output, text=True, check=True)
        if capture_output:
            return result.stdout.strip()
        return None
    except subprocess.CalledProcessError as e:
        print(f"Error running command: {' '.join(cmd)}")
        if e.stderr:
            print(f"Details: {e.stderr}")
        sys.exit(1)


def get_ecr_url():
    """Get ECR repository URL from Terraform output."""
    terraform_dir = Path(__file__).parent.parent.parent / "terraform" / "3_researcher"
    original_dir = os.getcwd()
    try:
        os.chdir(terraform_dir)
        return run_command(
            ["terraform", "output", "-raw", "ecr_repository_url"], capture_output=True
        )
    finally:
        os.chdir(original_dir)


def ecr_login(ecr_url):
    """Authenticate Docker with ECR."""
    password = run_command(
        ["aws", "ecr", "get-login-password", "--region", AWS_REGION, "--profile", AWS_PROFILE],
        capture_output=True,
    )
    login = subprocess.Popen(
        ["docker", "login", "--username", "AWS", "--password-stdin", ecr_url],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    _, stderr = login.communicate(input=password)
    if login.returncode != 0:
        print(f"Error logging into ECR: {stderr}")
        sys.exit(1)


def build_and_push(ecr_url, image_tag):
    """Build Docker image and push to ECR."""
    print(f"\nBuilding Docker image for linux/amd64 with tag: {image_tag}")
    run_command([
        "docker", "build", "--platform", "linux/amd64",
        "-t", f"{ECR_REPOSITORY}:{image_tag}", ".",
    ])

    print("\nTagging image for ECR...")
    run_command(["docker", "tag", f"{ECR_REPOSITORY}:{image_tag}", f"{ecr_url}:{image_tag}"])
    run_command(["docker", "tag", f"{ECR_REPOSITORY}:{image_tag}", f"{ecr_url}:latest"])

    print("\nPushing image to ECR...")
    run_command(["docker", "push", f"{ecr_url}:{image_tag}"])
    run_command(["docker", "push", f"{ecr_url}:latest"])


def update_app_runner(ecr_url, image_tag):
    """Find and update the App Runner service with the new image."""
    services = run_command([
        "aws", "apprunner", "list-services",
        "--region", AWS_REGION, "--profile", AWS_PROFILE,
        "--query", f"ServiceSummaryList[?ServiceName=='{SERVICE_NAME}'].ServiceArn",
        "--output", "json",
    ], capture_output=True)

    service_arns = json.loads(services) if services else []
    if not service_arns:
        print(f"\nApp Runner service '{SERVICE_NAME}' not found.")
        print("Run 'terraform apply' in terraform/3_researcher first.")
        return

    service_arn = service_arns[0]
    print(f"Found service: {service_arn}")

    # Get the current access role ARN
    access_role_arn = run_command([
        "aws", "apprunner", "describe-service",
        "--service-arn", service_arn,
        "--region", AWS_REGION, "--profile", AWS_PROFILE,
        "--query", "Service.SourceConfiguration.AuthenticationConfiguration.AccessRoleArn",
        "--output", "text",
    ], capture_output=True)

    # Update the service
    print(f"\nUpdating service to use image: {ecr_url}:{image_tag}")
    source_config = {
        "ImageRepository": {
            "ImageIdentifier": f"{ecr_url}:{image_tag}",
            "ImageConfiguration": {
                "Port": "8000",
                "RuntimeEnvironmentVariables": {
                    "AWS_DEFAULT_REGION": AWS_REGION,
                    "OPENAI_API_KEY": os.getenv("OPENAI_API_KEY", ""),
                    "AGENTRA_API_ENDPOINT": os.getenv("AGENTRA_API_ENDPOINT", ""),
                    "AGENTRA_API_KEY": os.getenv("AGENTRA_API_KEY", ""),
                },
            },
            "ImageRepositoryType": "ECR",
        },
        "AuthenticationConfiguration": {"AccessRoleArn": access_role_arn},
        "AutoDeploymentsEnabled": False,
    }

    run_command([
        "aws", "apprunner", "update-service",
        "--service-arn", service_arn,
        "--region", AWS_REGION, "--profile", AWS_PROFILE,
        "--source-configuration", json.dumps(source_config),
    ], capture_output=True)

    print("✅ Service update triggered!")
    wait_for_deployment(service_arn)


def wait_for_deployment(service_arn):
    """Poll App Runner until deployment completes."""
    print("\nWaiting for deployment (this may take 5-10 minutes)...")
    max_attempts = 120
    for attempt in range(max_attempts):
        status = run_command([
            "aws", "apprunner", "describe-service",
            "--service-arn", service_arn,
            "--region", AWS_REGION, "--profile", AWS_PROFILE,
            "--query", "Service.Status", "--output", "text",
        ], capture_output=True).strip()

        if status == "RUNNING":
            service_url = run_command([
                "aws", "apprunner", "describe-service",
                "--service-arn", service_arn,
                "--region", AWS_REGION, "--profile", AWS_PROFILE,
                "--query", "Service.ServiceUrl", "--output", "text",
            ], capture_output=True)
            print(f"\n✅ Deployment complete!")
            print(f"\n🚀 Service: https://{service_url}")
            print(f"   Health:  curl https://{service_url}/health")
            return

        if status == "OPERATION_IN_PROGRESS":
            print(".", end="", flush=True)
            if attempt > 0 and attempt % 6 == 0:
                print(f" ({(attempt * 5) / 60:.1f}m)", end="", flush=True)
            time.sleep(5)
        else:
            print(f"\n⚠️ Unexpected status: {status}")
            print("Check the AWS Console for details.")
            return

    print("\n⚠️ Deployment is taking longer than expected. Check the AWS Console.")


def main():
    print("Agentra Researcher — Deploy to App Runner")
    print("=" * 50)
    print(f"Profile: {AWS_PROFILE}")
    print(f"Region:  {AWS_REGION}")

    # Get ECR URL
    ecr_url = get_ecr_url()
    if not ecr_url:
        print("Error: ECR repository not found. Run 'terraform apply' first.")
        sys.exit(1)
    print(f"ECR:     {ecr_url}")

    # Login, build, push
    print("\nLogging in to ECR...")
    ecr_login(ecr_url)
    print("Login successful!")

    image_tag = f"deploy-{int(time.time())}"
    build_and_push(ecr_url, image_tag)
    print("\n✅ Image pushed successfully!")

    # Update App Runner
    print("\nUpdating App Runner service...")
    update_app_runner(ecr_url, image_tag)


if __name__ == "__main__":
    main()
