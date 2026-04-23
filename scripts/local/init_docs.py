from pathlib import Path

# Root directory (run from project root)
ROOT = Path(".")

# Folders to ignore
IGNORE = {".git", "node_modules", ".next", "__pycache__", "uv.lock"}

README_TEMPLATE = """# Overview
This module is part of Agentra.

## What it does
[Describe the purpose of this folder]

## How it fits into Agentra
[Explain how this component interacts with the system]
"""

AGENTS_TEMPLATE = """# Purpose
This folder contains logic related to Agentra.

# Responsibilities
- Define what belongs here
- Avoid placing unrelated logic here

# Key Files
- [file] → description

# Rules
- Follow Agentra architecture principles
- Keep logic modular and focused
"""


def should_skip(path: Path):
    return any(part in IGNORE for part in path.parts)


def create_file_if_missing(file_path: Path, content: str):
    if not file_path.exists():
        file_path.write_text(content)
        print(f"Created: {file_path}")
    else:
        # Only fill if empty
        if file_path.read_text().strip() == "":
            file_path.write_text(content)
            print(f"Filled empty file: {file_path}")


def main():
    for path in ROOT.rglob("*"):
        if path.is_dir() and not should_skip(path):
            readme = path / "README.md"
            agents = path / "AGENTS.md"

            create_file_if_missing(readme, README_TEMPLATE)
            create_file_if_missing(agents, AGENTS_TEMPLATE)


if __name__ == "__main__":
    main()