# Agentra

**Agentra** is an agentic AI-powered financial platform designed to provide continuous portfolio analysis, retirement planning, and intelligent financial advisory.

It combines a multi-agent architecture with cloud-native infrastructure to deliver real-time insights and long-term financial optimization.

---

## Overview

Agentra does the following:

* Analyzing equity portfolios
* Forecasting retirement outcomes
* Generating actionable financial insights
* Adapting strategies based on market conditions and user behavior

Agentra uses **agentic AI** to proactively manage and optimize financial decisions.

---

## Features

* **Multi-Agent System**

  * Planner Agent (orchestration)
  * Reporter Agent (portfolio analysis)
  * Retirement Agent(long-term planning)
  * Researcher Agent(market intelligence)
  * Tagger Agent(asset classification)
  * Charter Agent(visualization)

* **Portfolio Intelligence**

  * Performance analysis
  * Risk assessment
  * Diversification insights

* **Retirement Planning**

  * Scenario modeling
  * Goal tracking
  * Financial projections

* **Cloud-Native Architecture**

  * Serverless compute (AWS Lambda, App Runner)
  * Event-driven orchestration (SQS)
  * Scalable database (Aurora Serverless)

* **SaaS Platform**

  * Multi-user support
  * Secure data isolation
  * Web-based dashboard (Next.js)

---

## Architecture (High-Level)

```
User → Frontend (Next.js)
      → API Layer
      → Planner Agent (Orchestrator)
          ├── Reporter Agent
          ├── Retirement Agent
          ├── Researcher Agent
          ├── Tagger Agent
          └── Charter Agent
                ↓
          Aggregated Insights → Database → User
```

---

## Project Structure

```
backend/        # Agents, API, ingestion, database
frontend/       # Next.js SaaS dashboard
terraform/      # Infrastructure as Code (AWS)
docs/           # System-level documentation
guides/         # Step-by-step build roadmap
scripts/        # Deployment and utility scripts
env/            # Environment configurations
```

---

## Tech Stack

* **Backend:** Python (uv), FastAPI, OpenAI Agents SDK
* **Frontend:** Next.js (React)
* **Cloud:** AWS (Lambda, SQS, Aurora, App Runner, Bedrock)
* **AI/ML:** AWS Bedrock (Nova Pro), embeddings via SageMaker
* **Infrastructure:** Terraform

---

## Development Workflow

Branching strategy:

```
feature/* → dev → main
```

* `feature/*` → new features
* `dev` → integration branch
* `main` → production-ready

---

## Development Approach

This project follows a **sequential build strategy**:

1. Infrastructure setup
2. Data and ingestion pipeline
3. Multi-agent system
4. API and frontend
5. Production readiness

Each step builds toward a **fully functional SaaS system**.

---

## Status

Agentra is currently in active development.

* Core infrastructure and agents are being built incrementally
* Features are implemented step-by-step following the roadmap
* Documentation evolves alongside the system

---

Agentra aims to become:

> A fully autonomous financial intelligence platform that continuously analyzes, explains, and optimizes user wealth.

---

## Contributing

This is currently a focused development project. Contribution guidelines will be added as the system stabilizes.
