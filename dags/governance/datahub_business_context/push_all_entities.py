#!/usr/bin/env python3
"""Push all datahub_entities/*.datahub.yaml entity configs to DataHub in sequence.

Prerequisites:
    export DATAHUB_GRAPHQL_URL=https://<datahub-host>/api/graphql
    export DATAHUB_TOKEN=<personal-access-token-with-editor-role>

Optional — override the DataHub UI origin used when removing stale discovery links:
    export DATAHUB_UI_ORIGIN=https://datahub.apps.data-prd.habitat.zone

Usage:
    # Push all entities (skip _TEMPLATE and any _*.yaml):
    python dags/governance/datahub_business_context/push_all_entities.py

    # Push a single entity (same as calling the loader directly):
    python dags/governance/datahub_business_context/push_all_entities.py chatbot-sessions

Exit codes:
    0 — all entities pushed successfully
    1 — one or more entities failed or invalid invocation

Notes:
    - The loader is idempotent: re-running is safe and will upsert existing entities.
    - Entities are pushed sequentially (not in parallel) to avoid rate-limit issues.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

_SCRIPT_DIR = Path(__file__).resolve().parent
_ENTITY_CONFIG_DIR = _SCRIPT_DIR / "datahub_entities"
_LOADER = _SCRIPT_DIR / "load_collections_context.py"


def _resolve_target_configs(entity_arg: str | None) -> list[Path]:
    if entity_arg:
        slug = entity_arg.removesuffix(".datahub.yaml")
        path = _ENTITY_CONFIG_DIR / f"{slug}.datahub.yaml"
        if not path.is_file():
            print(f"ERROR: config not found: {path}", file=sys.stderr)
            sys.exit(1)
        return [path]

    configs = sorted(
        p
        for p in _ENTITY_CONFIG_DIR.glob("*.datahub.yaml")
        if not p.name.startswith("_")
    )
    if not configs:
        print(
            f"No *.datahub.yaml files found in {_ENTITY_CONFIG_DIR}",
            file=sys.stderr,
        )
        sys.exit(1)
    return configs


def main() -> int:
    graphql_url = os.environ.get("DATAHUB_GRAPHQL_URL", "").strip()
    if not graphql_url:
        print("ERROR: DATAHUB_GRAPHQL_URL is not set.", file=sys.stderr)
        print(
            "  export DATAHUB_GRAPHQL_URL=https://<datahub-host>/api/graphql",
            file=sys.stderr,
        )
        return 1

    token_set = bool(os.environ.get("DATAHUB_TOKEN", "").strip())
    if not token_set:
        print(
            "WARNING: DATAHUB_TOKEN is not set — mutations may fail.",
            file=sys.stderr,
        )

    entity_arg = sys.argv[1] if len(sys.argv) > 1 else None
    target_files = _resolve_target_configs(entity_arg)
    total = len(target_files)

    print(f"DataHub target  : {graphql_url}")
    print(f"Auth token      : {'set' if token_set else 'NOT SET'}")
    print(f"Entities to push: {total}")
    print("────────────────────────────────────────────────────────────")

    passed: list[str] = []
    failed: list[tuple[str, int]] = []

    for config_path in target_files:
        entity_name = config_path.name.removesuffix(".datahub.yaml")
        print("")
        print(f"▶  {entity_name}  ({config_path})")
        print("────────────────────────────────────────────────────────────")

        proc = subprocess.run(
            [sys.executable, str(_LOADER), "--config", str(config_path)],
            check=False,
        )
        if proc.returncode == 0:
            passed.append(entity_name)
        else:
            failed.append((entity_name, proc.returncode))
            print(
                f"  ✗ {entity_name} FAILED (exit {proc.returncode})",
                file=sys.stderr,
            )

    print("")
    print("════════════════════════════════════════════════════════════")
    print(f"Results: {len(passed)} passed / {len(failed)} failed / {total} total")

    if passed:
        print("")
        print("Passed:")
        for name in passed:
            print(f"  ✓ {name}")

    if failed:
        print("")
        print("Failed:")
        for name, code in failed:
            print(f"  ✗ {name} (exit {code})")
        return 1

    print("")
    print(f"All {total} entities pushed successfully.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
