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

# Fallback when listDomains returns empty (e.g. PAT missing Manage Domains /
# silent GraphQL errors). Search still lists DOMAIN entities for typical
# reader/editor tokens — same path DataHub MCP / UI uses.
_SEARCH_DOMAINS = """
query SearchDomains($input: SearchInput!) {
  search(input: $input) {
    start
    count
    total
    searchResults {
      entity {
        urn
        ... on Domain {
          properties {
            name
            description
          }
        }
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
    except urllib.error.HTTPError as exc:
        return None, f"http_{exc.code}"
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError):
        return None, "fetch_error"


def _format_graphql_errors(root: dict[str, Any] | None) -> str:
    if not root or not isinstance(root.get("errors"), list):
        return ""
    parts: list[str] = []
    for err in root["errors"][:5]:
        if isinstance(err, dict):
            msg = str(err.get("message") or err).strip()
        else:
            msg = str(err).strip()
        if msg:
            parts.append(msg)
    return "; ".join(parts)


def _graphql_data(
    graphql_url: str,
    token: Optional[str],
    query: str,
    variables: dict[str, Any],
) -> tuple[Optional[dict[str, Any]], str]:
    """Return ``(data, diagnostic)``. Diagnostic is empty on success."""
    root, diag = graphql_post(graphql_url, token, query, variables)
    if root is None:
        return None, diag or "fetch_error"
    gql_errs = _format_graphql_errors(root)
    if gql_errs:
        return None, f"graphql_errors: {gql_errs}"
    data = root.get("data")
    if not isinstance(data, dict):
        return None, "missing_data"
    return data, ""


def _domain_from_row(row: dict[str, Any]) -> DataHubDomain | None:
    urn = str(row.get("urn") or "").strip()
    if not urn:
        return None
    props = row.get("properties") if isinstance(row.get("properties"), dict) else {}
    name = str(props.get("name") or urn).strip()
    desc = str(props.get("description") or "").strip()
    return DataHubDomain(urn=urn, name=name, description=desc)


def _list_domains_page(
    graphql_url: str,
    token: Optional[str],
    *,
    start: int,
    parent_domain_urn: str | None,
) -> tuple[list[dict[str, Any]], str]:
    inp: dict[str, Any] = {"start": start, "count": _PAGE_SIZE}
    if parent_domain_urn:
        inp["parentDomain"] = parent_domain_urn

    data, diag = _graphql_data(graphql_url, token, _LIST_DOMAINS, {"input": inp})
    if not data:
        return [], diag
    block = data.get("listDomains") or {}
    rows = block.get("domains")
    return (rows if isinstance(rows, list) else []), ""


def _fetch_domains_via_list(
    graphql_url: str,
    token: Optional[str],
) -> tuple[dict[str, DataHubDomain], str]:
    """Walk listDomains (root + nested). Returns ``(by_urn, last_error)``."""
    by_urn: dict[str, DataHubDomain] = {}
    queue: list[str | None] = [None]
    last_diag = ""

    while queue:
        parent = queue.pop(0)
        start = 0
        while True:
            rows, diag = _list_domains_page(
                graphql_url, token, start=start, parent_domain_urn=parent
            )
            if diag:
                last_diag = diag
            if not rows:
                break
            for row in rows:
                if not isinstance(row, dict):
                    continue
                domain = _domain_from_row(row)
                if domain is None or domain.urn in by_urn:
                    continue
                by_urn[domain.urn] = domain
                queue.append(domain.urn)
            if len(rows) < _PAGE_SIZE:
                break
            start += _PAGE_SIZE

    return by_urn, last_diag


def _fetch_domains_via_search(
    graphql_url: str,
    token: Optional[str],
) -> tuple[dict[str, DataHubDomain], str]:
    """Flat DOMAIN search — used when listDomains yields nothing."""
    by_urn: dict[str, DataHubDomain] = {}
    start = 0
    last_diag = ""

    while True:
        data, diag = _graphql_data(
            graphql_url,
            token,
            _SEARCH_DOMAINS,
            {
                "input": {
                    "type": "DOMAIN",
                    "query": "*",
                    "start": start,
                    "count": _PAGE_SIZE,
                }
            },
        )
        if diag:
            last_diag = diag
        if not data:
            break
        block = data.get("search") or {}
        results = block.get("searchResults")
        if not isinstance(results, list) or not results:
            break
        for hit in results:
            if not isinstance(hit, dict):
                continue
            entity = hit.get("entity")
            if not isinstance(entity, dict):
                continue
            domain = _domain_from_row(entity)
            if domain is None or domain.urn in by_urn:
                continue
            by_urn[domain.urn] = domain
        if len(results) < _PAGE_SIZE:
            break
        start += _PAGE_SIZE

    return by_urn, last_diag


def fetch_all_domains(
    graphql_url: str,
    token: Optional[str],
) -> list[DataHubDomain]:
    """Return every domain in the catalog, deduped by URN.

    Prefers ``listDomains`` (preserves hierarchy for nested domains). If that
    returns zero rows, falls back to ``search(type: DOMAIN)`` so CI can still
    resolve ``domain_urn`` when the PAT cannot list domains but can search.
    """
    by_urn, list_diag = _fetch_domains_via_list(graphql_url, token)
    if by_urn:
        return sorted(by_urn.values(), key=lambda d: d.name.lower())

    by_urn, search_diag = _fetch_domains_via_search(graphql_url, token)
    if by_urn:
        if list_diag:
            print(
                f"WARN: listDomains returned 0 domains ({list_diag}); "
                f"using search fallback ({len(by_urn)} domains)."
            )
        else:
            print(
                f"WARN: listDomains returned 0 domains; "
                f"using search fallback ({len(by_urn)} domains)."
            )
        return sorted(by_urn.values(), key=lambda d: d.name.lower())

    details = []
    if list_diag:
        details.append(f"listDomains={list_diag}")
    if search_diag:
        details.append(f"search={search_diag}")
    if details:
        print(
            "ERROR: DataHub domain catalog empty after listDomains + search. "
            + "; ".join(details),
            flush=True,
        )
    return []


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
    data, _diag = _graphql_data(graphql_url, token, _ENTITY_EXISTS, {"urn": urn})
    if not data:
        return False
    return bool(data.get("entityExists"))
