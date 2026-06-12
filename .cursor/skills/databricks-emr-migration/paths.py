"""Repository path helpers for the migration validation skill."""

from __future__ import annotations

from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent
REPO_ROOT = SKILL_DIR.parents[2]
MIGRATION_EMR_CLI_ROOT = SKILL_DIR / "migration-emr-cli"
