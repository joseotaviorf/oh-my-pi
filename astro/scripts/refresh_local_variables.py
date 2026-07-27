#!/usr/bin/env python3
"""Regenerate astro/local_variables.json from forno Vault via qli.

Offline fallback seed for when VAULT_TOKEN is unavailable. VaultBackend is the
primary resolution path for local Airflow.

Usage:
  python3 astro/scripts/refresh_local_variables.py
  # or: make refresh-local-variables
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
OUT_PATH = REPO_ROOT / "astro" / "local_variables.json"
META_PATH = REPO_ROOT / "astro" / "local_variables.SOURCE.txt"
DEFAULT_ENV = "forno"
BASE_PATH = "apps/forno/astronomer/airflow/variables"

# Keys still consumed by dags/ or packages/ (see master-merge readiness audit).
LIVE_KEYS = (
    "AWS_DEFAULT_REGION",
    "DOC_MD_BASE_URL",
    "WONKA_START_DATE",
    "artifacts_bucket",
    "databricks_s3_bucket",
    "datalake_bucket",
    "dw_bucket",
    "emr_instance_profile_arn",
    "emr_service_role",
    "emr_subnet_id",
    "environment",
    "instance_profile_arn",
    "instance_profile_secret_arn_people",
    "instance_profile_secret_arn_reverse_listings_report",
    "instance_profile_secret_arn_vespucio",
    "spectrum_iam_role",
)


def _parse_qli_value(raw: str):
    payload = raw.removeprefix("value:")
    try:
        return json.loads(payload)
    except json.JSONDecodeError:
        return payload


def _fetch_variable(env_name: str, key: str):
    result = subprocess.run(
        ["qli", "kv", "get", "-e", env_name, f"{BASE_PATH}/{key}"],
        check=False,
        capture_output=True,
        text=True,
    )
    raw = (result.stdout or "").strip()
    if result.returncode != 0 or not raw:
        return None
    return _parse_qli_value(raw)


def _write_if_changed(path: Path, content: str) -> bool:
    """Skip the write when content is identical, keeping git status clean."""
    if path.is_file() and path.read_text() == content:
        return False
    path.write_text(content)
    return True


def main() -> int:
    env_name = os.environ.get("QLI_ENV", DEFAULT_ENV)

    if shutil.which("qli") is None:
        print("ERROR: qli not found on PATH", file=sys.stderr)
        return 1

    variables: dict = {}
    for key in LIVE_KEYS:
        value = _fetch_variable(env_name, key)
        if value is None:
            print(f"WARNING: missing {BASE_PATH}/{key} — skipping", file=sys.stderr)
            continue
        variables[key] = value

    seed = json.dumps(variables, indent=2, sort_keys=True) + "\n"
    meta = "\n".join(
        [
            "Offline fallback seed for local Airflow (astro/local_variables.json).",
            "Primary resolution is VaultBackend when VAULT_TOKEN is set",
            "(see astro/docker-compose.override.yml and make run-local-environment).",
            "",
            f"Source: qli kv get -e {env_name} {BASE_PATH}/<key>",
            "Regenerate: make refresh-local-variables",
            "",
        ]
    )
    changed = _write_if_changed(OUT_PATH, seed)
    changed |= _write_if_changed(META_PATH, meta)

    status = "updated" if changed else "unchanged"
    print(f"{OUT_PATH} ({len(variables)} live keys) + {META_PATH}: {status}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
