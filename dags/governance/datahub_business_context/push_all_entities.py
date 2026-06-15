#!/usr/bin/env python3
"""Deprecated wrapper — use generate_and_push_datahub_entities.py instead.

Markdown is the versioned source of truth. This script forwards to the CI
generator with ``--all`` for backward compatibility.

Usage:
    python dags/governance/datahub_business_context/push_all_entities.py
    python dags/governance/datahub_business_context/push_all_entities.py accounting-funnel

Requires OPENAI_API_KEY, DATAHUB_GRAPHQL_URL, and DATAHUB_TOKEN.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

_SCRIPT_DIR = Path(__file__).resolve().parent
_REPO_ROOT = _SCRIPT_DIR.parents[2]
_GENERATE_SCRIPT = (
    _REPO_ROOT
    / "packages/bietlejuice-compiler/scripts/ci_cd/generate_and_push_datahub_entities.py"
)
_MD_DIR = _REPO_ROOT / "docs/llm_context/business_entities"


def _md_for_slug(slug: str) -> Path:
    stem = slug.replace("-", "_")
    return _MD_DIR / f"{stem}.md"


def main() -> int:
    print(
        "NOTE: push_all_entities.py is deprecated. "
        "Forwarding to generate_and_push_datahub_entities.py",
        file=sys.stderr,
    )

    if not os.environ.get("OPENAI_API_KEY", "").strip():
        print(
            "ERROR: OPENAI_API_KEY is required for MD → YAML generation.",
            file=sys.stderr,
        )
        return 1

    cmd = [sys.executable, str(_GENERATE_SCRIPT)]
    if len(sys.argv) > 1:
        slug = sys.argv[1].removesuffix(".datahub.yaml")
        md_path = _md_for_slug(slug)
        if not md_path.is_file():
            print(f"ERROR: no MD found for slug {slug!r}: {md_path}", file=sys.stderr)
            return 1
        cmd.append(str(md_path))
    else:
        cmd.append("--all")

    proc = subprocess.run(cmd, cwd=_REPO_ROOT, check=False)
    return proc.returncode


if __name__ == "__main__":
    raise SystemExit(main())
