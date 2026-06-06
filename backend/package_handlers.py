#!/usr/bin/env python3
"""
Package slim handler zips for each agent.
Each zip contains ONLY the handler code + agentra-db src.
All shared dependencies live in the Lambda Layer (built by package_layer.py).
"""

import os
import sys
import shutil
import zipfile
import tempfile
from pathlib import Path


AGENT_FILES = {
    "tagger": ["lambda_handler.py", "agent.py", "templates.py", "observability.py"],
    "reporter": ["lambda_handler.py", "agent.py", "templates.py", "observability.py", "judge.py"],
    "charter": ["lambda_handler.py", "agent.py", "templates.py", "observability.py"],
    "retirement": ["lambda_handler.py", "agent.py", "templates.py", "observability.py"],
    "planner": ["lambda_handler.py", "agent.py", "templates.py", "observability.py", "market.py", "prices.py"],
}


def package_agent(agent_name: str, backend_dir: Path, db_src_dir: Path) -> bool:
    agent_dir = backend_dir / agent_name
    zip_path = agent_dir / f"{agent_name}_lambda.zip"

    print(f"\n📦 Packaging {agent_name.upper()} handler...")

    files = AGENT_FILES.get(agent_name, [])
    missing = [f for f in files if not (agent_dir / f).exists()]
    if missing:
        print(f"Missing files: {missing}")
        return False

    if zip_path.exists():
        zip_path.unlink()

    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        # Add handler files at root
        for filename in files:
            zf.write(agent_dir / filename, filename)

        # Add agentra-db src package (flat into zip root as src/)
        for src_file in db_src_dir.rglob("*.py"):
            arcname = "src/" + src_file.relative_to(db_src_dir).as_posix()
            zf.write(src_file, arcname)

    size_mb = zip_path.stat().st_size / (1024 * 1024)
    print(f"{zip_path.name} ({size_mb:.2f} MB)")
    return True


def main():
    backend_dir = Path(__file__).parent.absolute()
    db_src_dir = backend_dir / "database" / "src"

    if not db_src_dir.exists():
        print(f"Database src not found at {db_src_dir}")
        sys.exit(1)

    print("=" * 60)
    print("PACKAGING SLIM HANDLER ZIPS")
    print("=" * 60)
    print("(Dependencies are in the shared layer — not included here)")

    results = {}
    for agent in AGENT_FILES:
        results[agent] = package_agent(agent, backend_dir, db_src_dir)

    print("\n" + "=" * 60)
    success = sum(1 for v in results.values() if v)
    total = len(results)
    print(f"Packaged: {success}/{total}")

    for agent, ok in results.items():
        print(f"  {'✅' if ok else '❌'} {agent}")

    if success < total:
        sys.exit(1)

    print("\n✅ All handler zips ready!")
    print("Run: cd terraform/6_agents && terraform apply")


if __name__ == "__main__":
    main()
