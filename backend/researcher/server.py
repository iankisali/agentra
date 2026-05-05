"""
Agentra Researcher Service - Investment Research Agent
"""

import os
import logging
from datetime import datetime, UTC
from typing import Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from dotenv import load_dotenv
from agents import Agent, Runner, trace
from agents.extensions.models.litellm_model import LitellmModel

# Load environment before anything else
load_dotenv(override=True)

# Suppress LiteLLM warnings about optional dependencies
logging.getLogger("LiteLLM").setLevel(logging.CRITICAL)

# Import modules
from context import agent_instructions, DEFAULT_RESEARCH_PROMPT
from mcp_servers import playwright_mcp_server
from tools import ingest_financial_document

# --- Configuration ---
AWS_REGION = os.getenv("AWS_DEFAULT_REGION", "us-east-1")
BEDROCK_MODEL = os.getenv(
    "BEDROCK_MODEL", "bedrock/converse/us.anthropic.claude-3-7-sonnet-20250219-v1:0"
)

# Set region env vars once at startup
os.environ["AWS_REGION_NAME"] = AWS_REGION
os.environ["AWS_REGION"] = AWS_REGION
os.environ["AWS_DEFAULT_REGION"] = AWS_REGION

app = FastAPI(title="Agentra Researcher Service")


class ResearchRequest(BaseModel):
    topic: Optional[str] = None


async def run_research_agent(topic: str = None) -> str:
    """Run the research agent to generate investment research."""
    query = f"Research this investment topic: {topic}" if topic else DEFAULT_RESEARCH_PROMPT
    model = LitellmModel(model=BEDROCK_MODEL)

    with trace("Researcher"):
        async with playwright_mcp_server(timeout_seconds=60) as playwright_mcp:
            agent = Agent(
                name="Agentra Investment Researcher",
                instructions=agent_instructions(),
                model=model,
                tools=[ingest_financial_document],
                mcp_servers=[playwright_mcp],
            )
            result = await Runner.run(agent, input=query, max_turns=15)

    return result.final_output


@app.get("/")
async def root():
    return {
        "service": "Agentra Researcher",
        "status": "healthy",
        "timestamp": datetime.now(UTC).isoformat(),
    }


@app.get("/health")
async def health():
    """Health check with config status."""
    return {
        "service": "Agentra Researcher",
        "status": "healthy",
        "timestamp": datetime.now(UTC).isoformat(),
        "agentra_api_configured": bool(
            os.getenv("AGENTRA_API_ENDPOINT") and os.getenv("AGENTRA_API_KEY")
        ),
        "aws_region": AWS_REGION,
        "bedrock_model": BEDROCK_MODEL,
    }


@app.post("/research")
async def research(request: ResearchRequest):
    """
    Generate investment research.

    The agent will:
    1. Browse current financial websites for data
    2. Analyze the information found
    3. Store the analysis in the knowledge base

    If no topic is provided, the agent picks a trending topic.
    """
    try:
        response = await run_research_agent(request.topic)
        return {"status": "success", "result": response}
    except Exception as e:
        logging.exception("Error in /research")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/research/auto")
async def research_auto():
    """
    Automated research endpoint for scheduled runs.
    Used by EventBridge Scheduler for periodic research updates.
    """
    try:
        response = await run_research_agent(topic=None)
        return {
            "status": "success",
            "timestamp": datetime.now(UTC).isoformat(),
            "message": "Automated research completed",
            "preview": response[:200] + "..." if len(response) > 200 else response,
        }
    except Exception as e:
        logging.exception("Error in /research/auto")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
