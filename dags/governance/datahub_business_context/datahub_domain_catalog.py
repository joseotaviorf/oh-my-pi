"""Live DataHub domain catalog — fetch and validate domain URNs via GraphQL."""

from __future__ import annotations

import json
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any, Optional

_LIST_DOMAINS = """
query ListDomains($input: ListDomainsInput!) {
  listDomains(input: $input) {
    count
    total
    domains {
      urn
      properties {
        name
        description
      }
    }
  }
}
"""

_ENTITY_EXISTS = """
query EntityExists($urn: String!) {
  entityExists(urn: $urn)
}
"""

_PAGE_SIZE = 100


@dataclass(frozen=True)
class DataHubDomain:
    urn: str
    name: str
    description: str = ""


def graphql_post(
    graphql_url: str,
    token: Optional[str],
    query: str,
    variables: dict[str, Any],
    *,
    timeout_sec: float = 60.0,
) -> tuple[Optional[dict[str, Any]], str]:
    payload = json.dumps({"query": query, "variables": variables}).encode("utf-8")
    headers = {
        "Accept": "application/json",
        "Content-Type": "application/json",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"

    req = urllib.request.Request(
        graphql_url,
        data=payload,
        method="POST",
        headers=headers,
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout_sec) as resp:
            if int(getattr(resp, "status", None) or resp.getcode()) != 200:
                return None, "http_error"
            raw = resp.read()
            if not raw or not raw.strip():
                return None, "empty_body"
            return json.loads(raw.decode("utf-8")), "ok"
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError):
        return None, "fetch_error"


def _graphql_data(
    graphql_url: str,
    token: Optional[str],
    query: str,
    variables: dict[str, Any],
) -> Optional[dict[str, Any]]:
    root, _diag = graphql_post(graphql_url, token, query, variables)
    if root is None or root.get("errors"):
        return None
    data = root.get("data")
    return data if isinstance(data, dict) else None


def _list_domains_page(
    graphql_url: str,
    token: Optional[str],
    *,
    start: int,
    parent_domain_urn: str | None,
) -> list[dict[str, Any]]:
    inp: dict[str, Any] = {"start": start, "count": _PAGE_SIZE}
    if parent_domain_urn:
        inp["parentDomain"] = parent_domain_urn

    data = _graphql_data(graphql_url, token, _LIST_DOMAINS, {"input": inp})
    if not data:
        return []
    block = data.get("listDomains") or {}
    rows = block.get("domains")
    return rows if isinstance(rows, list) else []


def fetch_all_domains(
    graphql_url: str,
    token: Optional[str],
) -> list[DataHubDomain]:
    """Return every domain in the catalog (root + nested), deduped by URN."""
    by_urn: dict[str, DataHubDomain] = {}
    queue: list[str | None] = [None]

    while queue:
        parent = queue.pop(0)
        start = 0
        while True:
            rows = _list_domains_page(
                graphql_url, token, start=start, parent_domain_urn=parent
            )
            if not rows:
                break
            for row in rows:
                if not isinstance(row, dict):
                    continue
                urn = str(row.get("urn") or "").strip()
                if not urn or urn in by_urn:
                    continue
                props = (
                    row.get("properties")
                    if isinstance(row.get("properties"), dict)
                    else {}
                )
                name = str(props.get("name") or urn).strip()
                desc = str(props.get("description") or "").strip()
                by_urn[urn] = DataHubDomain(urn=urn, name=name, description=desc)
                queue.append(urn)
            if len(rows) < _PAGE_SIZE:
                break
            start += _PAGE_SIZE

    return sorted(by_urn.values(), key=lambda d: d.name.lower())


def known_domain_urns(domains: list[DataHubDomain]) -> frozenset[str]:
    return frozenset(d.urn for d in domains)


def format_domains_for_prompt(domains: list[DataHubDomain]) -> str:
    if not domains:
        return "(no domains returned — check DataHub permissions)"
    lines: list[str] = []
    for domain in domains:
        suffix = ""
        if domain.description:
            short = domain.description.replace("\n", " ").strip()
            if len(short) > 100:
                short = short[:97] + "..."
            suffix = f"  # {short}"
        lines.append(f'  - "{domain.name}" → {domain.urn}{suffix}')
    return "\n".join(lines)


def entity_exists(
    graphql_url: str,
    token: Optional[str],
    urn: str,
) -> bool:
    data = _graphql_data(graphql_url, token, _ENTITY_EXISTS, {"urn": urn})
    if not data:
        return False
    return bool(data.get("entityExists"))
