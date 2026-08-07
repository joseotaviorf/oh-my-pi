"""Minimal GitHub REST client for Luigi CI PR comments."""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from typing import Any, Optional

from sync.constants import GITHUB_REPO

__all__ = ["_api_request"]


def _github_token() -> str:
    token = os.environ.get("GITHUB_TOKEN", "").strip()
    if not token:
        raise RuntimeError("GITHUB_TOKEN is not set")
    return token


def _api_request(
    method: str,
    path: str,
    body: Optional[dict[str, Any]] = None,
) -> dict[str, Any]:
    token = _github_token()
    url = f"https://api.github.com/repos/{GITHUB_REPO}{path}"
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read().decode("utf-8")
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(
            f"GitHub API {method} {path} failed ({exc.code}): {detail}"
        ) from exc
