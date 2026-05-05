#!/usr/bin/env python3
"""
Test the researcher agent locally before deployment.
Uses the same model and config as server.py.
"""

import os
import asyncio
import logging

from dotenv import load_dotenv

load_dotenv(override=True)

from context import agent_instructions, DEFAULT_RESEARCH_PROMPT
from mcp_servers import playwright_mcp_server
from tools import ingest_financial_document
from agents import Agent, Runner
from agents.extensions.models.litellm_model import LitellmModel

# Suppress LiteLLM noise
logging.getLogger("LiteLLM").setLevel(logging.CRITICAL)

# Match server.py config
AWS_REGION = os.getenv("AWS_DEFAULT_REGION", "us-east-1")
BEDROCK_MODEL = os.getenv(
    "BEDROCK_MODEL", "bedrock/converse/us.anthropic.claude-3-7-sonnet-20250219-v1:0"
)

os.environ["AWS_REGION_NAME"] = AWS_REGION
os.environ["AWS_REGION"] = AWS_REGION
os.environ["AWS_DEFAULT_REGION"] = AWS_REGION


async def test_local(topic: str = None):
    """Test the researcher agent locally."""
    query = f"Research this investment topic: {topic}" if topic else DEFAULT_RESEARCH_PROMPT
    model = LitellmModel(model=BEDROCK_MODEL)

    print("Agentra Researcher — Local Test")
    print("=" * 60)
    print(f"Model:  {BEDROCK_MODEL}")
    print(f"Region: {AWS_REGION}")
    print(f"Query:  {query[:80]}...")
    print("=" * 60)

    try:
        async with playwright_mcp_server(timeout_seconds=60) as playwright_mcp:
            agent = Agent(
                name="Agentra Investment Researcher",
                instructions=agent_instructions(),
                model=model,
                tools=[ingest_financial_document],
                mcp_servers=[playwright_mcp],
            )
            result = await Runner.run(agent, input=query, max_turns=15)

        print("\nRESULT:")
        print("=" * 60)
        print(result.final_output)
        print("=" * 60)
        print("\n✅ Test completed successfully!")

    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    import sys

    topic = " ".join(sys.argv[1:]) if len(sys.argv) > 1 else None
    asyncio.run(test_local(topic))
