"""Shared DataHub GraphQL client wrapper for the TARS entity sync package."""

from __future__ import annotations

import json
import os
import sys
from typing import Any, Optional

_repo_root = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "..", "..")
)
_runtime_src = os.path.join(_repo_root, "packages", "bietlejuice-runtime", "src")
for _p in (_runtime_src, _repo_root):
    if _p not in sys.path:
        sys.path.insert(0, _p)

try:
    from bietlejuice.governance.fairness_assessment.datahub_graphql.client import (  # noqa: E402
        datahub_graphql_post,
    )
except ModuleNotFoundError:
    # Fallback for Airflow workers where bietlejuice is not installed (local/Astro dev).
    import urllib.error
    import urllib.request

    def datahub_graphql_post(  # type: ignore[misc]
        graphql_url: str,
        token: Optional[str],
        query: str,
        variables: dict[str, Any],
        timeout_sec: float = 60.0,
    ) -> tuple[Optional[dict[str, Any]], str]:
        payload = json.dumps({"query": query, "variables": variables}).encode("utf-8")
        req = urllib.request.Request(
            graphql_url,
            data=payload,
            method="POST",
            headers={"Accept": "application/json", "Content-Type": "application/json"},
        )
        if token:
            req.add_header("Authorization", f"Bearer {token}")
        try:
            with urllib.request.urlopen(req, timeout=timeout_sec) as resp:
                return json.loads(resp.read().decode("utf-8")), ""
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            return None, f"HTTP {exc.code}: {detail}"
        except Exception as exc:  # noqa: BLE001
            return None, str(exc)


GRAPHQL_URL: str = os.environ.get("DATAHUB_GRAPHQL_URL", "").strip()
TOKEN: Optional[str] = os.environ.get("DATAHUB_TOKEN", "").strip() or None


def post(
    query: str,
    variables: dict[str, Any],
    *,
    log_errors: bool = True,
) -> Optional[dict[str, Any]]:
    """POST a GraphQL query and return the ``data`` dict, or None on error."""
    root, _diag = datahub_graphql_post(GRAPHQL_URL, TOKEN, query, variables)
    if root is None or root.get("errors"):
        if log_errors and root and root.get("errors"):
            print(f"GraphQL errors: {json.dumps(root['errors'])}", file=sys.stderr)
        return None
    return root.get("data")
