"""Load Jira Ops API credentials from CI / shell environment."""

from __future__ import annotations

import json
import os
from typing import Any

JIRA_OPS_USERNAME = "JIRA_OPS_USERNAME"
JIRA_OPS_TOKEN = "JIRA_OPS_TOKEN"
JIRA_OPS_CLOUD_ID = "JIRA_OPS_CLOUD_ID"
JIRA_OPS_CREDENTIALS_JSON = "JIRA_OPS_CREDENTIALS_JSON"

_REQUIRED_KEYS = ("username", "token", "cloud_id")


def load_jiraops_credentials() -> dict[str, str]:
    """
    Resolve Jira Ops credentials from the environment.

    Supports either:
    - ``JIRA_OPS_CREDENTIALS_JSON``: JSON blob from Vault kv#value, or
    - ``JIRA_OPS_USERNAME`` / ``JIRA_OPS_TOKEN`` / ``JIRA_OPS_CLOUD_ID``: flat exports.
    """
    json_blob = os.environ.get(JIRA_OPS_CREDENTIALS_JSON)
    if json_blob:
        return _credentials_from_json_blob(json_blob)

    username = os.environ.get(JIRA_OPS_USERNAME)
    token = os.environ.get(JIRA_OPS_TOKEN)
    cloud_id = os.environ.get(JIRA_OPS_CLOUD_ID)
    if username and token and cloud_id:
        return {
            "username": username,
            "token": token,
            "cloud_id": cloud_id,
        }

    raise ValueError(
        "Jira Ops credentials not found. Set either "
        f"{JIRA_OPS_CREDENTIALS_JSON} (JSON with username, token, cloud_id from "
        f"Vault kv#value) or {JIRA_OPS_USERNAME}, {JIRA_OPS_TOKEN}, "
        f"{JIRA_OPS_CLOUD_ID}."
    )


def _credentials_from_json_blob(json_blob: str) -> dict[str, str]:
    try:
        parsed: Any = json.loads(json_blob)
    except json.JSONDecodeError as exc:
        raise ValueError(
            f"{JIRA_OPS_CREDENTIALS_JSON} is not valid JSON: {exc}"
        ) from exc

    if not isinstance(parsed, dict):
        raise ValueError(f"{JIRA_OPS_CREDENTIALS_JSON} must decode to a JSON object")

    missing = [key for key in _REQUIRED_KEYS if not parsed.get(key)]
    if missing:
        present = ", ".join(sorted(parsed))
        raise ValueError(
            f"{JIRA_OPS_CREDENTIALS_JSON} missing required keys: "
            f"{', '.join(missing)}. Present keys: {present}"
        )

    return {
        "username": str(parsed["username"]),
        "token": str(parsed["token"]),
        "cloud_id": str(parsed["cloud_id"]),
    }
