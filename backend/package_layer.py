#!/usr/bin/env python3
"""
Build a shared Lambda Layer for all Agentra agents.
Contains all heavy shared dependencies (litellm, langfuse, openai-agents, etc.)
Each agent zip only contains handler code + agentra-db, keeping them under 250MB unzipped.
"""

import os
import sys
import shutil
import tempfile
import subprocess
from pathlib import Path


def run_command(cmd, cwd=None):
    """Run a command and return output, exit on failure."""
    print(f"Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error:\n{result.stderr}")
        sys.exit(1)
    return result.stdout


def main():
    backend_dir = Path(__file__).parent.absolute()

    # Collect requirements from ALL agents (union of all dependencies)
    # so the shared layer covers any package that any agent imports
    AGENTS = ["tagger", "reporter", "charter", "retirement", "planner"]

    print("=" * 60)
    print("BUILDING SHARED LAMBDA LAYER")
    print("=" * 60)

    # Check Docker
    try:
        run_command(["docker", "--version"])
    except FileNotFoundError:
        print("Error: Docker not found")
        sys.exit(1)

    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)
        # Lambda layers must be under python/lib/python3.12/site-packages/
        layer_pkg_dir = temp_path / "python" / "lib" / "python3.12" / "site-packages"
        layer_pkg_dir.mkdir(parents=True)

        # Export requirements from each agent and merge them
        # Use package names only (no version pins) to let pip resolve compatible versions
        # across all agents' requirements without conflicts.
        print("\nExporting requirements from all agents...")
        package_names: set[str] = set()
        for agent in AGENTS:
            agent_dir = backend_dir / agent
            if not (agent_dir / "uv.lock").exists():
                print(f"  Skipping {agent} (no uv.lock)")
                continue
            req_text = run_command(
                ["uv", "export", "--no-hashes", "--no-emit-project"],
                cwd=str(agent_dir),
            )
            for line in req_text.splitlines():
                stripped = line.strip()
                if not stripped or stripped.startswith("#") or stripped.startswith("-e "):
                    continue
                # Extract package name (strip version specifier and markers)
                pkg = stripped
                for sep in ("==", ">=", "<=", "~=", "!=", ">", "<", ";"):
                    if sep in pkg:
                        pkg = pkg.split(sep)[0].strip()
                        break
                if pkg:
                    package_names.add(pkg)

        all_requirements = sorted(package_names)
        print(f"  Combined {len(all_requirements)} unique packages across {len(AGENTS)} agents")

        EXCLUDE_PREFIXES = (
            "pyperclip",   # clipboard, not needed in Lambda
            "-e ",         # editable local installs (agentra-db)
            "temporalio",  # temporal.io - not used, 43MB transitive dep
            "grpcio",      # gRPC - not used directly
            "grpcio-",     # gRPC tools
            "hf-xet",      # HuggingFace XET transfer - not needed at runtime
            "hf_xet",
            "tokenizers",  # HuggingFace tokenizers - not needed at runtime
            "pygments",    # syntax highlighting - not needed at runtime
            "pywin32",     # Windows-only, not available for linux/amd64
            "colorama",    # Windows terminal colors, not needed in Lambda
        )
        EXCLUDE_CONTAINS = ("agentra-db",)

        filtered = []
        excluded = []
        for line in sorted(all_requirements):
            stripped = line.strip()
            if any(stripped.startswith(p) for p in EXCLUDE_PREFIXES):
                excluded.append(stripped)
                continue
            if any(s in stripped for s in EXCLUDE_CONTAINS):
                excluded.append(stripped)
                continue
            filtered.append(line)

        # Write cleanup script to temp dir, then run it inside Docker after pip install
        cleanup_script_path = temp_path / "cleanup.py"
        cleanup_script_path.write_text('''
import os, shutil
root = "./python/lib/python3.12/site-packages"
removed = 0
for dirpath, dirnames, filenames in os.walk(root, topdown=False):
    for d in list(dirnames):
        if d == "__pycache__" or d.endswith(".dist-info") or d == "tests" or d == "test":
            full = os.path.join(dirpath, d)
            try:
                shutil.rmtree(full)
                removed += 1
                dirnames.remove(d)
            except Exception:
                pass
    for f in filenames:
        if f.endswith((".pyc", ".pyo")):
            try:
                os.remove(os.path.join(dirpath, f))
                removed += 1
            except Exception:
                pass
print(f"Cleanup removed {removed} entries")
''')

        if excluded:
            print(f"Excluding {len(excluded)} packages from layer (bloat/local deps)")

        req_file = temp_path / "requirements.txt"
        req_file.write_text("\n".join(filtered))

        print(f"\nInstalling {len(filtered)} packages into layer...")

        # Build inside Lambda container for linux/amd64 compatibility
        docker_cmd = [
            "docker", "run", "--rm",
            "--platform", "linux/amd64",
            "-v", f"{temp_path}:/build",
            "--entrypoint", "/bin/bash",
            "public.ecr.aws/lambda/python:3.12",
            "-c",
            "cd /build && pip install --timeout 300 --retries 5 "
            "--target ./python/lib/python3.12/site-packages "
            "-r requirements.txt && python3 cleanup.py",
        ]
        run_command(docker_cmd)

        # Zip the layer
        layer_zip = backend_dir / "shared_layer.zip"
        if layer_zip.exists():
            layer_zip.unlink()

        print(f"\nCreating layer zip: {layer_zip}")
        run_command(["zip", "-r", str(layer_zip), "python"], cwd=str(temp_path))

        size_mb = layer_zip.stat().st_size / (1024 * 1024)
        print(f"\nLayer created: {layer_zip} ({size_mb:.1f} MB compressed)")

        if size_mb > 250:
            print("Warning: Layer exceeds 250MB — consider splitting further")
        else:
            print("Layer size is within Lambda limits")

    print("\n📝 Next steps:")
    print("1. Run each agent's package_handler.py to build slim handler zips")
    print("2. Run terraform apply in terraform/6_agents to deploy the layer + functions")


if __name__ == "__main__":
    main()
