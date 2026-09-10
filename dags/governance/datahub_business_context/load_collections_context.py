"""Push curated business context into DataHub via GraphQL mutations.

Orchestration only — table registries, copy, glossary, and Golden SQL payload live in sibling
bundle modules selected by YAML ``bundle_id`` (when using ``kind: full_curated_datahub_bundle``).

**Configuration is YAML-first** (`spec_version: 1`). Use ``--config`` to choose a preset file:

    # Heavyweight bundle example (datasets + glossary + Golden query + sidebar SP)
    python .../load_collections_context.py \\
      --config /path/to/ephemeral-or-reference.yaml

    # Lightweight curated product (datasets + links + YAML-driven golden query)
    python .../load_collections_context.py \\
      --config /path/to/ephemeral-or-reference.yaml

``full_curated_datahub_bundle``: seven-step pipeline (editable dataset docs, schema field docs if
provided by the bundle, glossary terms from the bundle, Data Product lifecycle, glossary attach +
documentation link from the bundle, Golden ``createQuery``, merge-preserving sidebar structured
property + legacy ``removeLink`` cleanup). Payload and default URNs are supplied by Python modules
such as ``collections_recovery_bundle.py`` — not by this orchestrator.

``data_product_curated_entity``: declarative YAML only — the shape produced by CI from
``docs/llm_context/domain_entities/_TEMPLATE.md`` (``data_product_type: domain``) or
``docs/llm_context/metric_entities/_TEMPLATE.md`` (``data_product_type: metric``). See
``reference/_TEMPLATE.datahub.yaml`` for the full schema.

Domain products: link owned ``datasets``, glossary, golden queries, documentation link, lifecycle
and type structured properties.

Both kinds: the ``owners`` block (``data_owner`` / ``data_steward`` email lists, CI-injected
from the ``## Ownership`` MD section) is declaratively synced onto the DataHub ownership aspect
(Business Owner / Data Steward types) — owners removed from the MD are removed in DataHub. An
accountable owner who never used DataHub (so has no CorpUser) is auto-provisioned as a minimal
CorpUser stub before assignment, so accountability is never lost to tool-access gaps.

Metric products: link Trino/Databricks tables and Superset dataset URNs from
``## Superset Golden Assets`` as reference assets on the product Summary; wire
``related_data_products`` to upstream domain products; golden-query ``subjects`` may
duplicate Trino tables for Query entity wiring. The optional ``mbr`` list (CI-injected
from the ``## MBR`` MD section) is synced onto the ``data_product.mbr`` and
``data_product.mbr_category`` structured properties (multi-valued and filterable). The
``catalog`` list (from the ``## Catalog`` MD table) is synced onto the single
``data_product.metrics`` structured property, one value per metric with its OKR /
Health Metric type embedded (e.g. ``"NPS True (OKR)"``) — every row is required to
carry a type before it reaches here, so the mapping is always exact, unlike the
retired ``data_product.metric_type`` property (a separate de-duplicated list with no
positional link back to the metric names), which is now actively cleared on every
sync. A metric whose MD dropped a section has the matching property cleared, so
DataHub stays in lockstep with the Markdown.

Full-overwrite semantics: the Markdown/YAML is the single source of truth. A republish
*reconciles* the product to the YAML — assets dropped from ``datasets`` are unlinked from
*this* product only (``_prune_stale_assets`` / ``batchRemoveFromDataProducts``) and legacy
structured properties named in ``legacy_qualified_names_to_drop`` are deleted
(``_drop_legacy_structured_properties``) — so editing the MD and re-pushing never leaves
orphaned assets or stale sidebar properties, and never strips a shared table from another
product that still declares it.

Usage:
    export DATAHUB_GRAPHQL_URL=https://<your-datahub-host>/api/graphql
    export DATAHUB_TOKEN=<personal-access-token-with-editor-role>
    # Optional: Habitat UI origin used when removing stale discovery links
    # export DATAHUB_UI_ORIGIN=https://datahub.apps.data-prd.habitat.zone

The mutations are written to be safe to retry: descriptions are upserts; creates are
best-effort with duplicate handling.

Exit codes: 0 = success; 1 = at least one step failed (see stderr).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from types import ModuleType
from typing import Any, Optional

import yaml

# ---------------------------------------------------------------------------
# Bootstrap: reuse the existing GraphQL client from bietlejuice
# ---------------------------------------------------------------------------

# Allow running from repo root without installing the package (runtime code lives
# under packages/bietlejuice-runtime/src on post-split layouts).
_repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
_runtime_src = os.path.join(_repo_root, "packages", "bietlejuice-runtime", "src")
for _p in (_runtime_src, _repo_root):
    if _p not in sys.path:
        sys.path.insert(0, _p)

from datahub_curated_urns import (  # noqa: E402
    STRUCTURED_PROPERTY_ENTITY_TYPE_DATA_PRODUCT,
    STRUCTURED_PROPERTY_ENTITY_TYPE_QUERY,
    STRUCTURED_PROPERTY_VALUE_TYPE_URN_POINTER,
    DataHubCuratedUrns,
    load_curated_urns_from_spec,
    structured_property_urn,
)

from bietlejuice.governance.fairness_assessment.datahub_graphql.client import (  # noqa: E402
    datahub_graphql_post,
)

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

SPEC_VERSION_EXPECTED = 1
KIND_FULL_CURATED_DATAHUB_BUNDLE = "full_curated_datahub_bundle"
KIND_DATA_PRODUCT_CURATED_ENTITY = "data_product_curated_entity"

_SCRIPT_DIR = Path(__file__).resolve().parent
_REFERENCE_DIR = _SCRIPT_DIR / "reference"
DEFAULT_CONFIG_PATH = _REFERENCE_DIR / "payments.datahub.yaml"

GRAPHQL_URL = os.environ.get("DATAHUB_GRAPHQL_URL", "").strip()
TOKEN: Optional[str] = os.environ.get("DATAHUB_TOKEN", "").strip() or None

PLATFORM = "databricks"

# Platform probe order for (schema, table) dataset resolution.
# _resolve_urn() tries each platform in order and returns the first URN found
# in DataHub. Add "glue" as the second entry when the Databricks → Glue
# migration completes and Glue datasets start appearing in DataHub.
_PLATFORM_PROBE_ORDER: list[tuple[str, str]] = [
    ("trino", "hive.{schema}.{table}"),
    ("databricks", "{schema}.{table}"),
    # ("glue", "{schema}.{table}"),  # enable after Databricks → Glue migration
]

# Per-run cache: avoids re-probing the same (schema, table) pair across steps.
_URN_CACHE: dict[tuple[str, str], str | None] = {}

FULL_CURATED_BUNDLE_IDS_SUPPORTED: tuple[str, ...] = ("collections_recovery",)

# Fallback anchors when YAML omits domain/glossary (presets normally set explicitly).
_FALLBACK_DOMAIN_URN = "urn:li:domain:fintech"
_FALLBACK_GLOSSARY_PARENT_NODE_URN = "urn:li:glossaryNode:fintech"

BUNDLE_YAML_RUNTIME: dict[str, str] = {}


@dataclass(frozen=True)
class ActiveFullCuratedBundle:
    bundle_module: ModuleType
    urns: DataHubCuratedUrns


_ACTIVE_FULL_CURATED_BUNDLE: ActiveFullCuratedBundle | None = None


def resolve_full_bundle_module(bundle_id: str) -> ModuleType:
    if bundle_id == "collections_recovery":
        import collections_recovery_bundle as m

        return m
    raise SystemExit(
        f"Unknown bundle_id {bundle_id!r}; "
        f"supported: {FULL_CURATED_BUNDLE_IDS_SUPPORTED}"
    )


def active_full_curated_bundle() -> ActiveFullCuratedBundle:
    if _ACTIVE_FULL_CURATED_BUNDLE is None:
        raise RuntimeError("Internal error: no active full curated bundle session.")
    return _ACTIVE_FULL_CURATED_BUNDLE


def curated_bundle_urns() -> DataHubCuratedUrns:
    return active_full_curated_bundle().urns


def _effective_bundle_domain_urn() -> str:
    return BUNDLE_YAML_RUNTIME.get("domain_urn", _FALLBACK_DOMAIN_URN)


def _effective_bundle_glossary_parent_node_urn() -> str:
    return BUNDLE_YAML_RUNTIME.get(
        "glossary_parent_node_urn",
        _FALLBACK_GLOSSARY_PARENT_NODE_URN,
    )


DATAHUB_UI_ORIGIN = os.environ.get(
    "DATAHUB_UI_ORIGIN", "https://datahub.apps.data-prd.habitat.zone"
).rstrip("/")


def load_yaml_spec(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf8") as fh:
        spec = yaml.safe_load(fh)
    if not isinstance(spec, dict):
        raise SystemExit(f"YAML spec must be a mapping: {path}")
    return spec


def _ensure_spec_supported(spec: dict[str, Any], path: Path) -> None:
    if spec.get("spec_version") != SPEC_VERSION_EXPECTED:
        raise SystemExit(
            f"{path}: unsupported spec_version (expected {SPEC_VERSION_EXPECTED})",
        )


def _urn_candidates(schema: str, table: str) -> list[str]:
    """All candidate DataHub URNs for (schema, table), in _PLATFORM_PROBE_ORDER."""
    return [
        f"urn:li:dataset:(urn:li:dataPlatform:{plat},{tmpl.format(schema=schema, table=table)},PROD)"
        for plat, tmpl in _PLATFORM_PROBE_ORDER
    ]


def _resolve_urn(schema: str, table: str) -> str | None:
    """Return the first DataHub-registered URN across platforms, or None.

    Probes _PLATFORM_PROBE_ORDER (Trino first, then Databricks, …). Caches
    results so the same pair is never looked up twice within one script run.
    """
    key = (schema, table)
    if key not in _URN_CACHE:
        for urn in _urn_candidates(schema, table):
            if _entity_exists(urn):
                _URN_CACHE[key] = urn
                break
        else:
            _URN_CACHE[key] = None
    return _URN_CACHE[key]


# ---------------------------------------------------------------------------
# GraphQL helpers
# ---------------------------------------------------------------------------

_errors: list[str] = []

_GRAPHQL_MAX_ATTEMPTS = 3
_GRAPHQL_RETRYABLE_ERROR_SUBSTRINGS = (
    "timeout",
    "time out",
    "connection lease",
    "temporarily unavailable",
    "429",
    "502",
    "503",
    "504",
    "elasticsearch",
    "circuit breaker",
    "rate limit",
    "connection reset",
    "broken pipe",
)


def _graphql_errors_retryable(errors: list) -> bool:
    for err in errors or []:
        msg = (err.get("message") or "").lower()
        if any(sub in msg for sub in _GRAPHQL_RETRYABLE_ERROR_SUBSTRINGS):
            return True
    return False


_ALLOWED_REQUEST_SCHEMES = frozenset({"https", "http"})
# Destination allow-list (SSRF guard). This tool must only ever reach DataHub, which lives
# under the internal ``habitat.zone`` domain across environments; localhost covers local
# runs. The host of the configured DATAHUB_GRAPHQL_URL is always permitted as well, so a
# domain change never silently breaks the loader.
_ALLOWED_REQUEST_HOSTS = frozenset({"localhost", "127.0.0.1"})
_ALLOWED_REQUEST_HOST_SUFFIXES = (".habitat.zone",)


def _host_is_allowed(host: str) -> bool:
    if host in _ALLOWED_REQUEST_HOSTS:
        return True
    if any(host.endswith(suffix) for suffix in _ALLOWED_REQUEST_HOST_SUFFIXES):
        return True
    configured = (urllib.parse.urlparse(GRAPHQL_URL).hostname or "").lower()
    return bool(configured) and host == configured


def _assert_safe_url(url: str) -> str:
    """Validate a request URL before it reaches urllib (SSRF guard, CWE-918).

    Enforces an ``http(s)`` scheme, a non-empty host, and that the host is in the DataHub
    allow-list — so a malformed or unexpected value can never be turned into a request to
    an arbitrary target (file://, an internal metadata endpoint, an attacker host, …).
    Returns the URL unchanged when valid; raises ValueError otherwise.
    """
    parsed = urllib.parse.urlparse(url)
    host = (parsed.hostname or "").lower()
    if parsed.scheme not in _ALLOWED_REQUEST_SCHEMES or not host:
        raise ValueError(f"Refusing request to unsafe or non-HTTP(S) URL: {url!r}")
    if not _host_is_allowed(host):
        raise ValueError(
            f"Refusing request to host {host!r} — not in the DataHub allow-list"
        )
    return url


def _graphql_call_with_retry(
    query: str,
    variables: dict[str, Any],
    *,
    timeout_sec: float = 60.0,
) -> tuple[Optional[dict[str, Any]], str]:
    """POST GraphQL with retries on transient HTTP or GraphQL failures."""
    last_root: Optional[dict[str, Any]] = None
    last_diag = ""
    safe_url = _assert_safe_url(GRAPHQL_URL)

    for attempt in range(1, _GRAPHQL_MAX_ATTEMPTS + 1):
        root, diag = datahub_graphql_post(
            safe_url,
            TOKEN,
            query,
            variables,
            timeout_sec=timeout_sec,
        )
        last_root, last_diag = root, diag

        if root is None:
            if attempt < _GRAPHQL_MAX_ATTEMPTS:
                delay_s = 2**attempt
                print(
                    f"    WARN: DataHub HTTP failure ({diag}) — "
                    f"retry {attempt}/{_GRAPHQL_MAX_ATTEMPTS - 1} in {delay_s}s",
                    file=sys.stderr,
                )
                time.sleep(delay_s)
                continue
            return None, diag

        gql_errors = root.get("errors")
        if gql_errors and _graphql_errors_retryable(gql_errors):
            if attempt < _GRAPHQL_MAX_ATTEMPTS:
                delay_s = 2**attempt
                print(
                    f"    WARN: DataHub transient GraphQL error — "
                    f"retry {attempt}/{_GRAPHQL_MAX_ATTEMPTS - 1} in {delay_s}s: "
                    f"{json.dumps(gql_errors)}",
                    file=sys.stderr,
                )
                time.sleep(delay_s)
                continue

        return root, diag

    return last_root, last_diag


def _post(query: str, variables: dict[str, Any]) -> Optional[dict[str, Any]]:
    if not GRAPHQL_URL:
        raise RuntimeError(
            "DATAHUB_GRAPHQL_URL is not set. Export it before running this script."
        )
    root, diag = _graphql_call_with_retry(query, variables)
    if root is None:
        print(f"    [DEBUG] HTTP-level failure, diag={diag}", file=sys.stderr)
        return None
    gql_errors = root.get("errors")
    if gql_errors:
        print(f"    [DEBUG] GraphQL errors: {json.dumps(gql_errors)}", file=sys.stderr)
        return None
    return root.get("data")


def _ok(label: str, data: Any = None) -> None:
    print(f"  \u2713 {label}")


def _fail(label: str, detail: str) -> None:
    msg = f"  \u2717 {label}: {detail}"
    print(msg, file=sys.stderr)
    _errors.append(msg)


def _graphql_root(query: str, variables: dict[str, Any]) -> Optional[dict]:
    """Returns the full GraphQL JSON body (possibly with ``errors``) or None on HTTP failure."""
    root, diag = _graphql_call_with_retry(query, variables)
    if root is None:
        print(f"    [DEBUG] HTTP-level failure, diag={diag}", file=sys.stderr)
    return root


def _errors_indicate_already_exists(errors: list) -> bool:
    for err in errors or []:
        lower = (err.get("message") or "").lower()
        if "already exist" in lower or "duplicate" in lower or "duplicatekey" in lower:
            return True
    return False


def _graphql_field(data: Optional[dict[str, Any]], field: str) -> dict[str, Any]:
    """Return a GraphQL object field; JSON ``null`` is treated as missing."""
    if not isinstance(data, dict):
        return {}
    block = data.get(field)
    return block if isinstance(block, dict) else {}


def _data_product_exists(dp_urn: str) -> bool:
    data = _post(_CHECK_DATA_PRODUCT, {"urn": dp_urn})
    return bool(_graphql_field(data, "dataProduct").get("urn"))


_ENTITY_EXISTS = """
query EntityExists($urn: String!) {
  entityExists(urn: $urn)
}
"""


def _entity_exists(urn: str) -> bool:
    data = _post(_ENTITY_EXISTS, {"urn": urn})
    return bool(data and data.get("entityExists"))


def _gms_base_url_from_graphql(graphql_url: str) -> str:
    url = graphql_url.rstrip("/")
    marker = "/api/graphql"
    if url.endswith(marker):
        return url[: -len(marker)]
    return url


def _glossary_term_id_from_urn(urn: str) -> str:
    prefix = "urn:li:glossaryTerm:"
    urn = str(urn or "").strip()
    if urn.startswith(prefix):
        return urn[len(prefix) :]
    return ""


def _glossary_term_urn_exists(urn: str) -> bool:
    return _fetch_glossary_term(urn) is not None


_SEARCH_GLOSSARY_TERMS_BY_NAME = """
query SearchGlossaryTermsByName($input: SearchInput!) {
  search(input: $input) {
    searchResults {
      entity {
        urn
        ... on GlossaryTerm {
          properties {
            name
          }
        }
      }
    }
  }
}
"""


def _fetch_glossary_term(urn: str) -> dict[str, Any] | None:
    """Return glossary term payload when ``urn`` is a real catalog entity (not a shell)."""
    urn = str(urn or "").strip()
    if not urn.startswith("urn:li:glossaryTerm:"):
        return None
    query = """
    query FetchGlossaryTerm($urn: String!) {
      glossaryTerm(urn: $urn) {
        urn
        properties {
          name
        }
      }
    }
    """
    root = _graphql_root(query, {"urn": urn})
    if not root or root.get("errors"):
        return None
    term = (root.get("data") or {}).get("glossaryTerm")
    if not isinstance(term, dict):
        return None
    props = term.get("properties")
    if not isinstance(props, dict):
        return None
    if not str(props.get("name") or "").strip():
        return None
    resolved = str(term.get("urn") or "").strip()
    if resolved != urn:
        return None
    return term


def _lookup_glossary_term_urn_by_name(label: str, term_id: str = "") -> str | None:
    """Resolve an existing glossary term URN by display name or slug similarity."""
    name = str(label or "").strip()
    term_id = str(term_id or "").strip()
    if not name and not term_id:
        return None
    search_queries: list[str] = []
    if name:
        search_queries.append(name)
        if " / " in name:
            search_queries.append(name.split(" / ", 1)[0].strip())
    if term_id:
        search_queries.append(term_id.replace("_", " "))
    seen_queries: set[str] = set()
    slug_candidates: list[str] = []
    for query_text in search_queries:
        if not query_text or query_text in seen_queries:
            continue
        seen_queries.add(query_text)
        root = _graphql_root(
            _SEARCH_GLOSSARY_TERMS_BY_NAME,
            {
                "input": {
                    "query": query_text,
                    "type": "GLOSSARY_TERM",
                    "start": 0,
                    "count": 25,
                }
            },
        )
        if not root or root.get("errors"):
            continue
        rows = (
            ((root.get("data") or {}).get("search") or {}).get("searchResults")
        ) or []
        exact: str | None = None
        casefold: str | None = None
        name_key = name.casefold() if name else ""
        for row in rows:
            entity = row.get("entity") if isinstance(row, dict) else None
            if not isinstance(entity, dict):
                continue
            props = (
                entity.get("properties")
                if isinstance(entity.get("properties"), dict)
                else {}
            )
            candidate_name = str(props.get("name") or "").strip()
            candidate_urn = str(entity.get("urn") or "").strip()
            if not candidate_urn.startswith("urn:li:glossaryTerm:"):
                continue
            slug_candidates.append(candidate_urn)
            if name and candidate_name == name:
                exact = candidate_urn
                break
            if name and candidate_name.casefold() == name_key and casefold is None:
                casefold = candidate_urn
        if exact:
            return exact
        if casefold:
            return casefold
    if term_id:
        for candidate_urn in dict.fromkeys(slug_candidates):
            candidate_id = _glossary_term_id_from_urn(candidate_urn)
            if candidate_id == term_id:
                return candidate_urn
            if term_id in candidate_id or candidate_id in term_id:
                return candidate_urn
    return None


def _resolve_glossary_term_urn(term_id: str, label: str) -> str | None:
    """Return a catalog-backed glossary term URN for YAML ``id`` / display name."""
    by_id_urn = _glossary_term_urn(term_id)
    if _fetch_glossary_term(by_id_urn) is not None:
        return by_id_urn
    by_name = _lookup_glossary_term_urn_by_name(label, term_id=term_id)
    if by_name:
        print(
            f"  -> resolved {label!r} by name to {by_name} "
            f"(yaml id {term_id!r} not in catalog)"
        )
        return by_name
    return None


def _filter_existing_glossary_term_urns(urns: list[str]) -> list[str]:
    kept: list[str] = []
    for urn in urns:
        if _fetch_glossary_term(urn) is not None:
            kept.append(urn)
        else:
            print(
                f"  ! skipping attach for missing glossary term URN: {urn}",
                file=sys.stderr,
            )
    return kept


_CHECK_QUERY_EXISTS = """
query CheckQueryExists($urn: String!) {
  query(urn: $urn) {
    urn
    properties {
      name
    }
  }
}
"""


def _query_exists(urn: str) -> bool:
    urn = str(urn or "").strip()
    if not urn.startswith("urn:li:query:"):
        return False
    root = _graphql_root(_CHECK_QUERY_EXISTS, {"urn": urn})
    if not root or root.get("errors"):
        return False
    node = (root.get("data") or {}).get("query")
    if not isinstance(node, dict):
        return False
    props = node.get("properties")
    if not isinstance(props, dict):
        return False
    if not str(props.get("name") or "").strip():
        return False
    resolved = str(node.get("urn") or "").strip()
    return resolved == urn


def _gms_ingest_proposal(proposal: dict[str, Any]) -> tuple[bool, str]:
    """POST a MetadataChangeProposal wrapper to GMS REST ingest."""
    base = _gms_base_url_from_graphql(GRAPHQL_URL)
    url = _assert_safe_url(f"{base.rstrip('/')}/aspects?action=ingestProposal")
    payload = json.dumps(proposal).encode("utf-8")
    # Build the Request from the validated URL + static headers only. The request body
    # (the MD-derived proposal) is passed as urlopen's separate ``data`` argument rather
    # than embedded in the Request, so the value used as the request target is provably
    # the allow-listed URL and never the payload (avoids conflating body with URL).
    req = urllib.request.Request(
        url,
        method="POST",
        headers={
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
    )
    if TOKEN:
        req.add_header("Authorization", f"Bearer {TOKEN}")
    try:
        with urllib.request.urlopen(req, data=payload, timeout=60.0) as resp:
            status = int(getattr(resp, "status", None) or resp.getcode())
            if 200 <= status < 300:
                return True, "ok"
            body = resp.read().decode("utf-8", errors="replace")[:500]
            return False, f"HTTP {status}: {body}"
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")[:500]
        return False, f"HTTP {exc.code}: {body}"
    except Exception as exc:  # pragma: no cover - network guard
        return False, str(exc)


def _ingest_query_at_urn(
    query_urn: str,
    name: str,
    description: str,
    sql_text: str,
    subject_dataset_urns: list[str],
) -> bool:
    """Upsert a Query entity at a stable URN via GMS REST (GraphQL createQuery cannot)."""
    now_ms = int(time.time() * 1000)
    actor = "urn:li:corpuser:datahub"
    audit = {"time": now_ms, "actor": actor}
    properties_aspect = {
        "customProperties": {},
        "name": name,
        "description": description or name,
        "statement": {"value": sql_text, "language": "SQL"},
        "source": "MANUAL",
        "created": audit,
        "lastModified": audit,
    }
    subjects_aspect = {
        "subjects": [{"entity": urn} for urn in sorted(set(subject_dataset_urns))]
    }
    for aspect_name, aspect_body in (
        ("queryProperties", properties_aspect),
        ("querySubjects", subjects_aspect),
    ):
        proposal = {
            "proposal": {
                "entityType": "query",
                "entityUrn": query_urn,
                "changeType": "UPSERT",
                "aspectName": aspect_name,
                "aspect": {
                    "contentType": "application/json",
                    "value": json.dumps(aspect_body),
                },
            }
        }
        ok, detail = _gms_ingest_proposal(proposal)
        if not ok:
            print(
                f"    [DEBUG] ingestProposal {aspect_name} failed: {detail}",
                file=sys.stderr,
            )
            return False
    return True


# ---------------------------------------------------------------------------
# Mutation 1 — Dataset descriptions
# ---------------------------------------------------------------------------

_UPDATE_DATASET_DESCRIPTION = """
mutation UpdateDatasetDescription($urn: String!, $description: String!) {
  updateDataset(urn: $urn, input: {
    editableProperties: { description: $description }
  }) {
    urn
  }
}
"""


def push_dataset_descriptions() -> None:
    print("\n[1/7] Pushing dataset descriptions...")
    bm = active_full_curated_bundle().bundle_module
    editable = bm.merged_editable_dataset_urn_rows()
    for key, urn in editable.items():
        desc = bm.DATASET_DESCRIPTIONS.get(key)
        if not desc:
            _fail(key, "no description defined — skipping")
            continue
        data = _post(_UPDATE_DATASET_DESCRIPTION, {"urn": urn, "description": desc})
        if data and data.get("updateDataset"):
            _ok(key)
        else:
            _fail(key, f"mutation returned unexpected response: {data}")


# ---------------------------------------------------------------------------
# Mutation 2 — schemaField descriptions
# ---------------------------------------------------------------------------

_UPDATE_FIELD_DESCRIPTION = """
mutation UpdateFieldDescription(
  $description: String!,
  $resourceUrn: String!,
  $fieldPath: String!
) {
  updateDescription(input: {
    description: $description,
    resourceUrn: $resourceUrn,
    subResource: $fieldPath,
    subResourceType: DATASET_FIELD
  })
}
"""


def push_schema_field_descriptions() -> None:
    print("\n[2/7] Pushing schemaField descriptions...")
    bm = active_full_curated_bundle().bundle_module
    for table_key, fields in bm.SCHEMA_FIELD_DESCRIPTIONS.items():
        urn = bm.DATASET_URNS.get(table_key)
        if not urn:
            _fail(
                table_key, "URN not found in bundle dataset registry — skipping table"
            )
            continue
        for field_path, description in fields.items():
            label = f"{table_key}.{field_path}"
            data = _post(
                _UPDATE_FIELD_DESCRIPTION,
                {
                    "description": description,
                    "resourceUrn": urn,
                    "fieldPath": field_path,
                },
            )
            if data is not None and data.get("updateDescription") is not False:
                _ok(label)
            else:
                _fail(label, f"unexpected response: {data}")


# ---------------------------------------------------------------------------
# Mutation 3 — Glossary terms
# ---------------------------------------------------------------------------

# createGlossaryTerm returns a plain String (the URN), not an object.
_CREATE_GLOSSARY_TERM = """
mutation CreateGlossaryTerm($input: CreateGlossaryEntityInput!) {
  createGlossaryTerm(input: $input)
}
"""

_SEARCH_GLOSSARY_TERM = """
query SearchGlossaryTerm($id: String!) {
  glossaryTerm(urn: $urn) {
    urn
  }
}
"""


def _glossary_term_urn(term_id: str) -> str:
    return f"urn:li:glossaryTerm:{term_id}"


def _term_exists(term_id: str) -> bool:
    """Return True when ``urn:li:glossaryTerm:{term_id}`` resolves in DataHub."""
    return _fetch_glossary_term(_glossary_term_urn(term_id)) is not None


def push_glossary_terms() -> None:
    print("\n[3/7] Pushing glossary terms...")
    bm = active_full_curated_bundle().bundle_module
    for term in bm.GLOSSARY_TERMS:
        label = term["name"]
        term_id = term["id"]

        if _term_exists(term_id):
            print(f"  \u2192 {label}: already exists — skipping create")
        else:
            payload: dict[str, Any] = {
                "id": term_id,
                "name": term["name"],
                "description": term["description"],
            }
            glossary_parent = _effective_bundle_glossary_parent_node_urn()
            if glossary_parent:
                payload["parentNode"] = glossary_parent

            root = _graphql_root(_CREATE_GLOSSARY_TERM, {"input": payload})
            errs = (root or {}).get("errors") or []
            data = (root or {}).get("data") if not errs else {}
            if data.get("createGlossaryTerm"):
                _ok(f"{label} ({data['createGlossaryTerm']})")
            elif errs and _errors_indicate_already_exists(errs):
                print(f"  \u2192 {label}: already exists — skipping create")
            else:
                _fail(label, f"unexpected response: {data}")
                continue

        rt = term.get("related_terms") or []
        if rt:
            _push_term_related_terms(_glossary_term_urn(term_id), rt)


def _push_term_related_terms(
    source_urn: str,
    related_terms_cfg: list[dict[str, str]],
) -> None:
    """Wire DataHub Glossary Related Term relationships for a single term.

    Each entry in *related_terms_cfg* is a dict with:
      ``urn``          – the other glossary term's URN
      ``relationship`` – one of: isA | inherits | inherited_by | hasA | contains | contained_by

    For ``contained_by`` / ``inherited_by`` the source/target are swapped so that
    the relationship is always declared on the semantically correct owner side.
    """
    for entry in related_terms_cfg:
        other_urn = str(entry.get("urn") or "").strip()
        rel_key = str(entry.get("relationship") or "").strip()
        if not other_urn or not rel_key:
            _fail(
                f"related_term for {source_urn}",
                f"missing 'urn' or 'relationship' in entry: {entry}",
            )
            continue

        other_id = _glossary_term_id_from_urn(other_urn)
        if not _glossary_term_urn_exists(other_urn):
            resolved_other = _resolve_glossary_term_urn(
                other_id,
                str(entry.get("name") or other_id.replace("_", " ")),
            )
            if resolved_other:
                other_urn = resolved_other

        gql_type = _RELATIONSHIP_TYPE_MAP.get(rel_key)
        if gql_type is None:
            _fail(
                f"related_term for {source_urn}",
                f"unknown relationship {rel_key!r}; "
                f"valid: {sorted(_RELATIONSHIP_TYPE_MAP)}",
            )
            continue

        if rel_key in _REVERSE_RELATIONSHIP_KEYS:
            mutation_source, mutation_targets = other_urn, [source_urn]
        else:
            mutation_source, mutation_targets = source_urn, [other_urn]

        if not _glossary_term_urn_exists(mutation_source):
            print(
                f"  ! skipping related term (missing source): {source_urn}",
                file=sys.stderr,
            )
            continue
        missing_targets = [
            u for u in mutation_targets if not _glossary_term_urn_exists(u)
        ]
        if missing_targets:
            print(
                f"  ! skipping related term (missing target): "
                f"{source_urn} --[{rel_key}]--> {other_urn}",
                file=sys.stderr,
            )
            continue

        if mutation_source in mutation_targets:
            print(
                f"  ! skipping self-referential related term: "
                f"{mutation_source} --[{rel_key}]--> {other_urn}",
                file=sys.stderr,
            )
            continue

        label = f"{source_urn} --[{rel_key}]--> {other_urn}"
        data = _post(
            _ADD_RELATED_TERMS,
            {
                "input": {
                    "urn": mutation_source,
                    "termUrns": mutation_targets,
                    "relationshipType": gql_type,
                }
            },
        )
        if data is not None and data.get("addRelatedTerms") is not False:
            _ok(f"Related term: {label}")
        else:
            _fail(f"addRelatedTerms {label}", f"unexpected response: {data}")


# ---------------------------------------------------------------------------
# Mutation 4 — DataProduct
# ---------------------------------------------------------------------------

_CREATE_DATA_PRODUCT = """
mutation CreateDataProduct($input: CreateDataProductInput!) {
  createDataProduct(input: $input) {
    urn
  }
}
"""

_UPDATE_DATA_PRODUCT = """
mutation UpdateDataProduct($urn: String!, $input: UpdateDataProductInput!) {
  updateDataProduct(urn: $urn, input: $input) {
    urn
  }
}
"""

_SET_DATA_PRODUCT_ASSETS = """
mutation BatchSetDataProductAssets($input: BatchSetDataProductInput!) {
  batchSetDataProduct(input: $input)
}
"""

# Scoped unlink: drop assets from *these* products only. Never substitute
# ``batchSetDataProduct`` with a null ``dataProductUrn`` — that unsets the asset
# from every Data Product (see BatchSetDataProductInput.dataProductUrn).
_REMOVE_FROM_DATA_PRODUCTS = """
mutation BatchRemoveFromDataProducts($input: BatchSetDataProductsInput!) {
  batchRemoveFromDataProducts(input: $input)
}
"""

_CHECK_DATA_PRODUCT = """
query CheckDataProduct($urn: String!) {
  dataProduct(urn: $urn) { urn }
}
"""


def _data_product_urn(product_id: str) -> str:
    return f"urn:li:dataProduct:{product_id}"


def push_data_product() -> None:
    print("\n[4/7] Pushing DataProduct...")
    bm = active_full_curated_bundle().bundle_module
    cx = curated_bundle_urns()
    dp_urn = cx.data_product_urn

    # Always attempt creation; DataHub returns a GraphQL error if it already exists.
    # In that case the urn field is absent from the response, so we fall through to
    # asset linking (the product exists from a prior run).
    create_data = _post(
        _CREATE_DATA_PRODUCT,
        {
            "input": {
                "id": cx.data_product_id,
                "properties": {
                    "name": bm.DATA_PRODUCT_NAME,
                    "description": bm.DATA_PRODUCT_DESCRIPTION,
                },
                "domainUrn": _effective_bundle_domain_urn(),
            }
        },
    )
    if create_data and _graphql_field(create_data, "createDataProduct").get("urn"):
        _ok(f"Created {bm.DATA_PRODUCT_NAME} ({dp_urn})")
    else:
        # Could be an "already exists" error from a prior run — that is fine.
        print(
            f"  \u2192 {bm.DATA_PRODUCT_NAME}: creation returned no URN "
            "(may already exist) — proceeding to asset linking"
        )

    # Link assets
    asset_data = _post(
        _SET_DATA_PRODUCT_ASSETS,
        {
            "input": {
                "dataProductUrn": dp_urn,
                "resourceUrns": cx.dataset_resource_urns,
            }
        },
    )
    if asset_data is not None:
        _ok(
            f"Linked {len(cx.dataset_resource_urns)} datasets to {bm.DATA_PRODUCT_NAME}"
        )
    else:
        _fail(
            f"asset linking for {bm.DATA_PRODUCT_NAME}",
            f"unexpected response: {asset_data}",
        )


# ---------------------------------------------------------------------------
# Mutation 4b — DataProduct enrichments (glossary terms + GitHub resource)
# ---------------------------------------------------------------------------

_ADD_LINK = """
mutation AddLink($input: AddLinkInput!) {
  addLink(input: $input)
}
"""

_BATCH_ADD_TERMS = """
mutation BatchAddTerms($input: BatchAddTermsInput!) {
  batchAddTerms(input: $input)
}
"""

_ADD_RELATED_TERMS = """
mutation AddRelatedTerms($input: RelatedTermsInput!) {
  addRelatedTerms(input: $input)
}
"""

# Maps human-friendly YAML values to the DataHub TermRelationshipType enum.
# DataHub exposes only two enum values: isA and hasA.
# "contained_by" and "inherited_by" are inverse views — handled by swapping
# source / target in the mutation call (see _REVERSE_RELATIONSHIP_KEYS).
_RELATIONSHIP_TYPE_MAP: dict[str, str] = {
    "isA": "isA",
    "inherits": "isA",
    "inherited_by": "isA",
    "hasA": "hasA",
    "contains": "hasA",
    "contained_by": "hasA",
}
_REVERSE_RELATIONSHIP_KEYS = frozenset({"inherited_by", "contained_by"})


def push_data_product_enrichments() -> None:
    """Attach glossary terms and GitHub documentation link to the DataProduct."""
    print("\n[5/7] Enriching DataProduct (terms + GitHub resource)...")
    bm = active_full_curated_bundle().bundle_module
    cx = curated_bundle_urns()
    dp_urn = cx.data_product_urn

    # --- GitHub documentation link ---
    root_gh = _graphql_root(
        _ADD_LINK,
        {
            "input": {
                "linkUrl": cx.documentation_github_url,
                "label": bm.DOCUMENTATION_LINK_LABEL,
                "resourceUrn": dp_urn,
            }
        },
    )
    errs_gh = (root_gh or {}).get("errors") or []
    data_gh = (root_gh or {}).get("data") if not errs_gh else {}
    if data_gh and data_gh.get("addLink") is not None:
        _ok("Linked GitHub documentation to DataProduct")
    elif errs_gh and _errors_indicate_already_exists(errs_gh):
        _ok("GitHub documentation link (already on DataProduct)")
    elif errs_gh:
        print(f"    [DEBUG] GraphQL errors: {json.dumps(errs_gh)}", file=sys.stderr)
        _fail("addLink", "GitHub resource link failed")
    else:
        _fail("addLink", "GitHub resource link failed (empty response)")

    # --- Glossary terms ---
    terms_data = _post(
        _BATCH_ADD_TERMS,
        {
            "input": {
                "termUrns": cx.data_product_attached_glossary_term_urns,
                "resources": [{"resourceUrn": dp_urn}],
            }
        },
    )
    if terms_data and terms_data.get("batchAddTerms"):
        _ok(
            f"Attached {len(cx.data_product_attached_glossary_term_urns)} "
            "glossary terms to DataProduct",
        )
    else:
        _fail("batchAddTerms", f"unexpected response: {terms_data}")


# ---------------------------------------------------------------------------
# Mutation 6 — Golden query
# ---------------------------------------------------------------------------

_CREATE_QUERY = """
mutation CreateQuery($input: CreateQueryInput!) {
  createQuery(input: $input) {
    urn
  }
}
"""


_SEARCH_QUERIES = """
query DhSearchQueries($frag: String!) {
  search(
    input: { query: $frag, type: QUERY, start: 0, count: 35 }
  ) {
    searchResults {
      entity {
        urn
      }
    }
  }
}
"""


def push_golden_query() -> None:
    print("\n[6/7] Pushing golden Query entity (no Summary resource link)...")
    bm = active_full_curated_bundle().bundle_module
    cx = curated_bundle_urns()
    # Note: `source` is not available in this DataHub version's CreateQueryInput.
    data = _post(
        _CREATE_QUERY,
        {
            "input": {
                "properties": {
                    "name": bm.GOLDEN_QUERY_NAME,
                    "description": bm.GOLDEN_QUERY_ENTITY_DESCRIPTION,
                    "statement": {
                        "value": bm.AR_RECOVERY_RATE_SQL,
                        "language": "SQL",
                    },
                },
                "subjects": [
                    {"datasetUrn": urn} for urn in cx.golden_query_subject_urns
                ],
            }
        },
    )
    if data and _graphql_field(data, "createQuery").get("urn"):
        _ok(f"Created query: {bm.GOLDEN_QUERY_NAME}")
    else:
        _fail(bm.GOLDEN_QUERY_NAME, f"unexpected response: {data}")


_REMOVE_LINK = """
mutation RemoveGoldenQueryLink($input: RemoveLinkInput!) {
  removeLink(input: $input)
}
"""


def _maybe_remove_golden_query_discovery_link() -> None:
    """Drop legacy golden-query URL from the Data Product Summary (Resources)."""

    cx = curated_bundle_urns()
    dp_urn = cx.data_product_urn
    root = _graphql_root(
        _REMOVE_LINK,
        {
            "input": {
                "linkUrl": cx.golden_query_ui_summary_url(DATAHUB_UI_ORIGIN),
                "label": cx.golden_query_discovery_link_removal_label,
                "resourceUrn": dp_urn,
            }
        },
    )
    if root is None:
        return
    errs = root.get("errors") or []
    data = root.get("data") if not errs else {}
    if errs:
        for err in errs:
            msg = (err.get("message") or "").lower()
            if "not found" in msg or "does not exist" in msg or "unknown" in msg:
                _ok("Golden-query discovery link (already absent)")
                return
        print(
            f"    [DEBUG] removeLink response: {json.dumps(root)}",
            file=sys.stderr,
        )
        _fail(
            "removeLink (golden query)",
            "could not remove stale discovery link (see stderr)",
        )
        return

    rl = data.get("removeLink")
    if rl is True or rl is False or rl is None:
        _ok("Golden-query discovery link cleanup finished")


# ---------------------------------------------------------------------------
# Mutation 7 — Golden query structured property (Data Product sidebar)
# ---------------------------------------------------------------------------
# upsertStructuredProperties replaces all structured properties on the asset;
# we pre-fetch existing properties and merge so sibling keys are preserved.

_FETCH_DATA_PRODUCT_STRUCTURED_PROPERTIES = """
query FetchDataProductStructuredProperties($urn: String!) {
  dataProduct(urn: $urn) {
    urn
    structuredProperties {
      properties {
        structuredProperty {
          urn
        }
        values {
          ... on StringValue {
            stringValue
          }
          ... on NumberValue {
            numberValue
          }
        }
        valueEntities {
          urn
        }
      }
    }
  }
}
"""

_CREATE_STRUCTURED_PROPERTY = """
mutation CreateStructuredPropertyGoldenQuery($input: CreateStructuredPropertyInput!) {
  createStructuredProperty(input: $input) {
    urn
  }
}
"""

_UPSERT_STRUCTURED_PROPERTIES = """
mutation UpsertStructuredPropertiesGoldenQuery($input: UpsertStructuredPropertiesInput!) {
  upsertStructuredProperties(input: $input) {
    properties {
      structuredProperty {
        urn
      }
    }
  }
}
"""


def _structured_property_entry_to_value_inputs(
    prop: dict[str, Any],
) -> Optional[list[dict[str, Any]]]:
    """Rebuild PropertyValueInput rows for merge (string/number union and/or resolved URN entities)."""

    values = prop.get("values") or []
    value_entities = prop.get("valueEntities") or []

    out: list[dict[str, Any]] = []
    saw_unsupported_value = False
    for raw in values:
        if not isinstance(raw, dict):
            return None
        if raw.get("stringValue") is not None:
            out.append({"stringValue": raw["stringValue"]})
        elif raw.get("numberValue") is not None:
            out.append({"numberValue": raw["numberValue"]})
        elif not any(v is not None for v in raw.values()):
            continue
        else:
            saw_unsupported_value = True
            break

    if saw_unsupported_value:
        out = []

    if out:
        return out

    for ent in value_entities:
        if not isinstance(ent, dict):
            return None
        urn = ent.get("urn")
        if not urn:
            return None
        out.append({"stringValue": urn})

    return out if out else None


def _duplicate_structured_property_message(errors: list[Any]) -> bool:
    """Treat createStructuredProperty duplicates as success (definition already present)."""

    for err in errors or []:
        msg = (err.get("message") or "").lower()
        if "duplicate" in msg and "structured" in msg:
            return True
        if "already exists" in msg and ("property" in msg or "qualified" in msg):
            return True
    return False


def _ensure_structured_property(qname: str, inp: dict[str, Any], label: str) -> bool:
    """Idempotent createStructuredProperty: skips via entityExists pre-check, returns True on success.

    Retains the error-based fallback for TOCTOU races where entityExists returns False
    but createStructuredProperty still bounces with "already exists".
    """
    if _entity_exists(structured_property_urn(qname)):
        _ok(f"Structured property already defined ({qname})")
        return True
    root = _graphql_root(_CREATE_STRUCTURED_PROPERTY, {"input": inp})
    if root is None:
        _fail(f"createStructuredProperty ({label})", "HTTP/network failure")
        return False
    gql_errors = root.get("errors")
    if gql_errors:
        if _errors_indicate_already_exists(
            gql_errors
        ) or _duplicate_structured_property_message(gql_errors):
            _ok(f"Structured property already defined ({qname})")
            return True
        _fail(f"createStructuredProperty ({label})", json.dumps(gql_errors))
        return False
    data = root.get("data") or {}
    created = data.get("createStructuredProperty")
    urn_resp = created.get("urn") if isinstance(created, dict) else None
    if urn_resp:
        _ok(f"Defined structured property {urn_resp}")
        return True
    _fail(f"createStructuredProperty ({label})", f"unexpected response: {data}")
    return False


def ensure_dp_golden_struct_property(qualified_name: str) -> None:
    """Idempotent CreateStructuredProperty: URN type restricted to Query, MULTIPLE cardinality."""
    _ensure_structured_property(
        qualified_name,
        {
            "qualifiedName": qualified_name,
            "id": qualified_name,
            "displayName": "Golden query",
            "description": (
                "Canonical validated SQL for this Data Product, stored as Query entities "
                "(navigable from the sidebar)."
            ),
            "valueType": STRUCTURED_PROPERTY_VALUE_TYPE_URN_POINTER,
            "typeQualifier": {"allowedTypes": [STRUCTURED_PROPERTY_ENTITY_TYPE_QUERY]},
            "cardinality": "MULTIPLE",
            "entityTypes": [STRUCTURED_PROPERTY_ENTITY_TYPE_DATA_PRODUCT],
            "settings": {
                "showInAssetSummary": True,
                "hideInAssetSummaryWhenEmpty": True,
                "showInSearchFilters": False,
                "isHidden": False,
                "showAsAssetBadge": False,
                "showInColumnsTable": False,
            },
        },
        "golden query",
    )


def ensure_golden_query_structured_property_definition() -> None:
    nm = curated_bundle_urns().golden_query_structured_property_qualified_name
    ensure_dp_golden_struct_property(nm)


def _merged_dp_structured_props(
    dp_urn: str,
    *,
    golden_sp_qname: str,
    golden_query_urn_vals: list[str],
    legacy_skip_urns: Optional[frozenset[str]] = None,
) -> Optional[list[dict[str, Any]]]:
    """Merge existing Data Product structured properties with golden-query sidebar entry.

    ``golden_query_urn_vals`` is a list — the golden-query structured property is MULTIPLE
    cardinality, so all of a product's Query URNs land in the sidebar.
    """

    golden_sp_urn = structured_property_urn(golden_sp_qname)
    our_row = {
        "structuredPropertyUrn": golden_sp_urn,
        "values": [{"stringValue": u} for u in golden_query_urn_vals],
    }
    legacy_skip = set(legacy_skip_urns or frozenset())
    fetch = _post(_FETCH_DATA_PRODUCT_STRUCTURED_PROPERTIES, {"urn": dp_urn})
    if fetch is None:
        print(
            "    Prefetch structured properties failed (GraphQL errors or HTTP failure).",
            file=sys.stderr,
        )
        return None
    dp_blob = fetch.get("dataProduct")
    if dp_blob is None:
        print(
            "    dataProduct(...) returned null — cannot merge structured properties.",
            file=sys.stderr,
        )
        return None

    props = (
        ((dp_blob.get("structuredProperties") or {}).get("properties")) or []
    ) or []
    if not props:
        return [our_row]

    merged: list[dict[str, Any]] = []
    for prop in props:
        sp_blob = prop.get("structuredProperty") or {}
        sp_u = sp_blob.get("urn")
        if not sp_u:
            continue
        if sp_u == golden_sp_urn:
            continue
        if sp_u in legacy_skip:
            q_disp = (
                sp_u.replace("urn:li:structuredProperty:", "", 1)
                if "structuredProperty:" in sp_u
                else sp_u
            )
            print(
                "    Dropping legacy structured property from Data Product merge "
                f"({q_disp}).",
                file=sys.stderr,
            )
            continue
        converted = _structured_property_entry_to_value_inputs(prop)
        if converted is None:
            print(
                f"    Cannot merge sibling structured property {sp_u}: "
                "could not round-trip values — use OpenAPI PATCH or remove conflicting "
                "properties before running this loader.",
                file=sys.stderr,
            )
            return None
        merged.append({"structuredPropertyUrn": sp_u, "values": converted})

    merged.append(our_row)
    return merged


def _merged_structured_property_input_params(
    dp_urn: str,
) -> Optional[list[dict[str, Any]]]:
    cx = curated_bundle_urns()

    return _merged_dp_structured_props(
        dp_urn,
        golden_sp_qname=cx.golden_query_structured_property_qualified_name,
        golden_query_urn_vals=[cx.golden_query_urn],
        legacy_skip_urns=cx.legacy_structured_property_urns_to_drop,
    )


def push_golden_query_structured_property() -> None:
    """Set golden query as a URN structured property → Query entity link in sidebar (showInAssetSummary)."""

    print("\n[7/7] Golden query structured property (Data Product sidebar)...")
    _maybe_remove_golden_query_discovery_link()
    ensure_golden_query_structured_property_definition()
    dp_urn = curated_bundle_urns().data_product_urn

    merged = _merged_structured_property_input_params(dp_urn)
    if merged is None:
        _fail(
            "upsertStructuredProperties (golden query)",
            "skipped: merge preflight failed (see stderr); no destructive upsert applied",
        )
        return

    data = _post(
        _UPSERT_STRUCTURED_PROPERTIES,
        {
            "input": {
                "assetUrn": dp_urn,
                "structuredPropertyInputParams": merged,
            },
        },
    )
    up_resp = (data or {}).get("upsertStructuredProperties")
    if data is not None and up_resp is not None:
        _ok(f"Upserted structured properties on Data Product ({len(merged)} key(s))")
    else:
        _fail(
            "upsertStructuredProperties (golden query)",
            f"unexpected response: {data}",
        )


# ---------------------------------------------------------------------------
# Curated Entity preset (YAML kind: data_product_curated_entity)
# ---------------------------------------------------------------------------


def _get_all_golden_queries(cfg: dict[str, Any]) -> list[dict[str, Any]]:
    """Normalize golden queries to a list. Accepts plural ``golden_queries:`` (preferred)
    or singular ``golden_query:`` (legacy, treated as a one-item list)."""
    plural = cfg.get("golden_queries")
    if isinstance(plural, list):
        return [q for q in plural if isinstance(q, dict)]
    singular = cfg.get("golden_query")
    if isinstance(singular, dict):
        return [singular]
    return []


# FROM / JOIN ``schema.table`` references in a SQL statement. Only dotted (qualified)
# references match, so bare CTE aliases (``FROM actual_vol``) are naturally excluded.
_SQL_TABLE_REF_RE = re.compile(
    r"\b(?:FROM|JOIN)\s+([a-z][a-z0-9_]*)\.([a-z][a-z0-9_]*)",
    re.IGNORECASE,
)


def _table_refs_in_sql(sql: str) -> list[tuple[str, str]]:
    """Distinct ``(schema, table)`` pairs referenced in a query's FROM/JOIN clauses,
    in first-seen order. CTE aliases (unqualified names) are not matched."""
    seen: set[tuple[str, str]] = set()
    out: list[tuple[str, str]] = []
    for schema, table in _SQL_TABLE_REF_RE.findall(sql or ""):
        key = (schema.lower(), table.lower())
        if key not in seen:
            seen.add(key)
            out.append((schema, table))
    return out


def _subject_urns_from_sql(sql: str) -> list[str]:
    """Fallback subject resolution: derive dataset URNs from the query SQL's FROM/JOIN
    refs. Used when the YAML omits usable ``subjects`` — common for large multi-CTE
    golden queries where the generator fails to populate the field."""
    urns: list[str] = []
    for schema, table in _table_refs_in_sql(sql):
        resolved = _resolve_urn(schema, table)
        if resolved and resolved not in urns:
            urns.append(resolved)
    return urns


def _golden_query_subject_urns(
    gq: dict[str, Any], fallback_subject_urns: Optional[list[str]] = None
) -> list[str]:
    """Dataset URNs for one golden query's ``subjects`` (list of {schema, table}).

    Resolution order, stopping at the first that yields a DataHub-registered table:
      1. explicit ``subjects`` in the YAML;
      2. ``schema.table`` refs parsed from the query's own SQL (FROM/JOIN);
      3. ``fallback_subject_urns`` — a product-wide pool (the product's datasets plus
         tables seen across all its golden-query SQL). This rescues queries written as a
         final ``SELECT ... FROM <cte>`` over a shared base CTE (common in metric docs),
         whose own SQL references no real table.

    Returns an empty list only when none of the three yields anything — the caller
    (``_curated_push_one_golden_query``) then logs it without aborting the product run.
    """
    raw_subj = gq.get("subjects") or []
    rows = raw_subj if isinstance(raw_subj, list) else []
    urns: list[str] = []
    for row in rows:
        if isinstance(row, dict) and row.get("schema") and row.get("table"):
            resolved = _resolve_urn(str(row["schema"]), str(row["table"]))
            if resolved and resolved not in urns:
                urns.append(resolved)
    name = gq.get("name") or "<unnamed>"
    if not urns:
        # YAML subjects missing/unresolvable — recover them from the SQL itself.
        urns = _subject_urns_from_sql(str(gq.get("sql") or ""))
        if urns:
            print(
                f"  -> golden query {name!r}: derived {len(urns)} subject(s) from SQL "
                f"(YAML subjects were missing/unresolvable)"
            )
    if not urns and fallback_subject_urns:
        # SQL only touches shared CTEs — fall back to the product-wide subject pool.
        urns = list(fallback_subject_urns)
        print(
            f"  -> golden query {name!r}: using {len(urns)} product-level subject(s) "
            f"(query SQL referenced only CTEs)"
        )
    if not urns:
        print(
            f"  ! golden query {name!r} has no valid `subjects` — skipping",
            file=sys.stderr,
        )
    return urns


def _is_metric_product(cfg: dict[str, Any]) -> bool:
    """A metric Data Product documents an official calculated metric.

    It links reference assets on the product Summary — Trino/Databricks tables the metric
    reads (e.g. ``sandbox.nps_fr``) and Superset virtual-dataset URNs — plus upstream domain
    products via ``related_data_products``."""
    return str(cfg.get("data_product_type") or "").strip().lower() == "metric"


def _curated_data_product_asset_urns(cfg: dict[str, Any]) -> list[str]:
    rows = cfg.get("datasets") or []
    if not isinstance(rows, list) or not rows:
        # Metric products legitimately own no datasets — return an empty list and let the
        # caller create the Data Product without asset links. Domain products must declare
        # the tables they own, so an empty list there is still a hard error.
        if _is_metric_product(cfg):
            return []
        raise SystemExit("`datasets` (non-empty list) is required")
    out = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        if row.get("urn"):
            # Explicit URN — no platform probing (e.g. Superset chart datasets).
            out.append(str(row["urn"]))
        elif row.get("schema") and row.get("table"):
            schema, table = str(row["schema"]), str(row["table"])
            resolved = _resolve_urn(schema, table)
            if resolved:
                out.append(resolved)
            else:
                tried = ", ".join(
                    c.split("dataPlatform:")[1].split(",")[0]
                    for c in _urn_candidates(schema, table)
                )
                print(
                    f"  ! skipping dataset not in DataHub: {schema}.{table} "
                    f"(tried platforms: {tried})",
                    file=sys.stderr,
                )
        else:
            print(
                f"  ! skipping malformed dataset row (no 'urn' or 'schema'+'table'): {row}",
                file=sys.stderr,
            )
    return sorted(set(out))


def _curated_pending_dataset_names(cfg: dict[str, Any]) -> list[str]:
    """Return ``schema.table`` strings from cfg['datasets'] that couldn't be resolved.

    Relies on the ``_URN_CACHE`` already populated by a prior call to
    ``_curated_data_product_asset_urns`` within the same run, so no extra
    DataHub probes are made.
    """
    rows = cfg.get("datasets") or []
    if not isinstance(rows, list):
        return []
    pending = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        if row.get("urn"):
            continue  # explicit URN — assumed to exist
        schema = str(row.get("schema") or "").strip()
        table = str(row.get("table") or "").strip()
        if schema and table and _resolve_urn(schema, table) is None:
            pending.append(f"{schema}.{table}")
    return pending


def _curated_unlinked_dataset_names(
    cfg: dict[str, Any], linked_urns: set[str]
) -> list[str]:
    """Declared datasets that exist in DataHub but were not assigned this run.

    Typical cause: ownership lookup failed (fail-closed). Relies on ``_URN_CACHE``
    from a prior ``_curated_data_product_asset_urns`` call. A table already linked to
    another Data Product is still assignable — the same dataset may sit on several
    products.
    """
    rows = cfg.get("datasets") or []
    if not isinstance(rows, list):
        return []
    unlinked: list[str] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        if row.get("urn"):
            urn = str(row["urn"])
            label = urn
        else:
            schema = str(row.get("schema") or "").strip()
            table = str(row.get("table") or "").strip()
            if not schema or not table:
                continue
            urn = _resolve_urn(schema, table)
            label = f"{schema}.{table}"
        if urn and urn not in linked_urns:
            unlinked.append(label)
    return unlinked


def _may_publish_without_linked_assets(
    *, is_metric: bool, pending: list[str], unlinked: list[str]
) -> bool:
    """True when the Data Product should still be created with 0 dataset links."""
    return is_metric or bool(pending) or bool(unlinked)


_PENDING_TABLES_SENTINEL = "**Tables not yet available in DataHub**"
_UNLINKED_TABLES_SENTINEL = "**Tables not linked as Data Product assets**"


def _append_dataset_notes(
    description: str, pending: list[str], unlinked: list[str]
) -> str:
    """Append pending/unlinked table notes used by the post-push smoke skip."""
    parts = [description.rstrip()]
    if pending:
        parts.append(
            "\n\n---\n\n"
            f"{_PENDING_TABLES_SENTINEL} "
            "(will be linked automatically once ingested):\n"
            + "\n".join(f"- `{t}`" for t in sorted(pending))
        )
    if unlinked:
        parts.append(
            "\n\n---\n\n"
            f"{_UNLINKED_TABLES_SENTINEL} "
            "(ownership lookup failed this run; will retry on the next publish):\n"
            + "\n".join(f"- `{t}`" for t in sorted(unlinked))
        )
    return "".join(parts)


def _filter_registered_dataset_urns(urns: list[str]) -> list[str]:
    """Keep only dataset URNs that exist in DataHub (batchSet fails on unknown URNs)."""
    registered: list[str] = []
    for urn in urns:
        if _entity_exists(urn):
            registered.append(urn)
        else:
            print(f"  ! skipping dataset not in DataHub: {urn}")
    omitted = len(urns) - len(registered)
    if omitted:
        print(
            f"  -> using {len(registered)}/{len(urns)} datasets "
            f"({omitted} omitted — not registered in DataHub)"
        )
    return registered


# Reverse-relationship query: skip only when ownership cannot be determined (fail-closed).
# A dataset may already sit on another Data Product; that is not a conflict.
_GET_ASSET_OWNER_PRODUCT = """
query GetAssetOwnerProduct($urn: String!) {
  entity(urn: $urn) {
    relationships(input: {
      types: ["DataProductContains"], direction: INCOMING, start: 0, count: 1
    }) {
      relationships { entity { urn } }
    }
  }
}
"""


_OWNER_UNKNOWN = object()  # sentinel: lookup failed, cannot determine ownership


def _get_asset_current_product_urn(asset_urn: str) -> Any:
    """Return the Data Product URN that currently owns ``asset_urn``, or None.

    Returns the ``_OWNER_UNKNOWN`` sentinel when the GraphQL call fails or returns no
    data — callers must distinguish "unowned" (None) from "lookup error" (sentinel) so
    that transient API errors don't silently allow reassignment.

    Uses the INCOMING ``DataProductContains`` relationship via the generic ``entity``
    root query so datasets, charts, and dashboards are all supported.
    """
    try:
        data = _post(_GET_ASSET_OWNER_PRODUCT, {"urn": asset_urn})
    except Exception:
        return _OWNER_UNKNOWN
    entity_node = _graphql_field(data, "entity")
    if not entity_node:
        # GraphQL returned no data — cannot confirm unowned; treat as unknown.
        return _OWNER_UNKNOWN
    rels = (entity_node.get("relationships") or {}).get("relationships") or []
    for rel in rels:
        owner = ((rel or {}).get("entity") or {}).get("urn")
        if owner:
            return str(owner)
    return None


def _filter_assignable_urns(urns: list[str], this_product_urn: str) -> list[str]:
    """Keep datasets that can be linked to this product, including shared tables.

    The same dataset may belong to several Data Products (DataHub
    ``DataProductContains`` is not exclusive). Keep the asset when it is unowned,
    already on this product, or already on a *different* product.
    Skip (fail-closed) only when ownership cannot be determined — a transient API
    error must not drive assign/prune with incomplete information.
    """
    assignable: list[str] = []
    for urn in urns:
        owner = _get_asset_current_product_urn(urn)
        if owner is _OWNER_UNKNOWN:
            print(
                f"  ! ownership lookup failed for {urn} — skipping (fail-closed). "
                f"Retry when DataHub is reachable.",
                file=sys.stderr,
            )
        elif owner is None or owner == this_product_urn:
            assignable.append(urn)
        else:
            print(
                f"  -> sharing {urn} with {owner} (also linking to {this_product_urn})"
            )
            assignable.append(urn)
    skipped = len(urns) - len(assignable)
    if skipped:
        print(
            f"  -> assigning {len(assignable)}/{len(urns)} datasets "
            f"({skipped} skipped — ownership lookup failed)"
        )
    return assignable


_FETCH_DATA_PRODUCT_ASSETS = """
query FetchDataProductAssets($urn: String!) {
  dataProduct(urn: $urn) {
    entities(input: { query: "*", start: 0, count: 1000 }) {
      searchResults { entity { urn } }
    }
  }
}
"""


def _fetch_linked_asset_urns(dp_urn: str) -> set[str] | None:
    """URNs of every asset currently linked to the Data Product, or None on lookup failure."""
    data = _post(_FETCH_DATA_PRODUCT_ASSETS, {"urn": dp_urn})
    dp = _graphql_field(data, "dataProduct")
    if not dp:
        return None
    results = (dp.get("entities") or {}).get("searchResults") or []
    return {
        str((r.get("entity") or {}).get("urn"))
        for r in results
        if isinstance(r, dict) and (r.get("entity") or {}).get("urn")
    }


def _prune_stale_assets(dp_urn: str, desired_urns: list[str]) -> None:
    """Detach assets currently on THIS product that are no longer in the YAML.

    The Markdown is the single source of truth: an asset dropped from ``datasets`` (or a
    metric's ``## Superset Golden Assets``) is unlinked here so a republish converges to
    exactly the YAML set instead of accumulating orphans (``batchSetDataProduct`` only
    *adds* links).

    Removal uses ``batchRemoveFromDataProducts`` with this product's URN so other products
    that still list the same table keep their membership. Do **not** call
    ``batchSetDataProduct`` with a null ``dataProductUrn`` — that unsets the asset from
    every Data Product. Fail-open: a lookup or mutation failure logs and skips (never
    globally unsets, never deletes on incomplete information).
    """
    current = _fetch_linked_asset_urns(dp_urn)
    if current is None:
        print(
            "  ! could not fetch current assets — skipping stale-asset prune (fail-open)",
            file=sys.stderr,
        )
        return
    stale = sorted(current - set(desired_urns))
    if not stale:
        return
    data = _post(
        _REMOVE_FROM_DATA_PRODUCTS,
        {
            "input": {
                "dataProductUrns": [dp_urn],
                "resourceUrns": stale,
            }
        },
    )
    if data is None:
        print(
            "  ! batchRemoveFromDataProducts failed — skipping stale-asset prune "
            "(fail-open; will not globally unset shared tables)",
            file=sys.stderr,
        )
        return
    _ok(f"Unlinked {len(stale)} stale asset(s) no longer in YAML")
    for urn in stale:
        print(f"      - {urn}")


def _create_or_update_data_product(
    pid: str, pname: Any, pdesc_raw: Optional[str], dom: Any, dp_u: str
) -> bool:
    """Create the Data Product, or update it when it already exists.

    ``pdesc_raw`` is ``None`` for callers that don't own the description field
    (only push-datahub-business-context supplies a description, so it stays the sole
    writer of that field and never gets overwritten
    with the condensed TARS summary). When ``None``, the description key is omitted from
    both mutations: create leaves it unset, update leaves the existing value untouched.

    Returns True when the product exists afterward (created or updated); False on a hard
    failure (already recorded via ``_fail``)."""
    create_properties: dict[str, Any] = {"name": str(pname)}
    if pdesc_raw is not None:
        create_properties["description"] = pdesc_raw.strip()
    create_root = _graphql_root(
        _CREATE_DATA_PRODUCT,
        {
            "input": {
                "id": pid,
                "properties": create_properties,
                "domainUrn": str(dom),
            },
        },
    )
    if create_root is None:
        _fail("curated.createDataProduct", "HTTP failure")
        return False

    create_errors = create_root.get("errors") or []
    create_data = create_root.get("data") or {}
    create_dp = _graphql_field(
        create_data if isinstance(create_data, dict) else None,
        "createDataProduct",
    )
    if create_dp.get("urn"):
        _ok(f"Created DataProduct ({dp_u})")
        return True
    if _errors_indicate_already_exists(create_errors) or _data_product_exists(dp_u):
        update_input: dict[str, Any] = {"name": str(pname)}
        if pdesc_raw is not None:
            update_input["description"] = pdesc_raw.strip()
            print("  -> DataProduct already exists — updating description...")
        else:
            print(
                "  -> DataProduct already exists — updating name only "
                "(description is owned by push-datahub-business-context)..."
            )
        upd = _graphql_root(
            _UPDATE_DATA_PRODUCT,
            {
                "urn": dp_u,
                "input": update_input,
            },
        )
        updated_dp = (upd.get("data") or {}).get("updateDataProduct") if upd else None
        if not updated_dp:
            _fail("curated.updateDataProduct", repr(upd))
            return False
        _ok(
            "Updated DataProduct"
            + (" description" if pdesc_raw is not None else " name")
        )
        return True
    _fail(
        "curated.createDataProduct",
        json.dumps(create_errors or create_root, default=str),
    )
    return False


def curated_push_assets(cfg: dict[str, Any]) -> None:
    print("\n[1/13] DataProduct assets (datasets only)...")
    pid = str(cfg["data_product_id"])
    pname = cfg.get("product_display_name") or pid
    pdesc_raw = cfg.get("product_description")
    # product_description is optional: only push-datahub-business-context supplies it
    # (from the committed Markdown). Callers that omit it link datasets/owners/etc. below
    # without ever touching the description field, so it
    # stays single-writer.
    has_description = isinstance(pdesc_raw, str) and bool(pdesc_raw.strip())
    dom = cfg.get("domain_urn") or _FALLBACK_DOMAIN_URN

    dp_u = _data_product_urn(pid)
    # Resolve datasets. _curated_data_product_asset_urns populates _URN_CACHE so
    # the subsequent _curated_pending_dataset_names call needs no extra API probes.
    yaml_asset_urns = _curated_data_product_asset_urns(cfg)
    registered = _filter_registered_dataset_urns(yaml_asset_urns)
    urns = _filter_assignable_urns(registered, dp_u)
    pending = _curated_pending_dataset_names(cfg)
    unlinked = _curated_unlinked_dataset_names(cfg, set(urns))
    is_metric = _is_metric_product(cfg)

    if not urns and not _may_publish_without_linked_assets(
        is_metric=is_metric, pending=pending, unlinked=unlinked
    ):
        _fail(
            "curated.batchSetDataProduct",
            "no datasets from YAML are registered in DataHub",
        )
        return

    # Tables that don't exist in DataHub yet, or that this run could not assign
    # (ownership lookup failed), can't be linked. When this caller owns the description,
    # append their names so the post-push smoke does not treat a valid 0-asset publish
    # as a miss. Tables already on another product ARE linked (shared membership).
    if pending or unlinked:
        if has_description:
            pdesc_raw = _append_dataset_notes(str(pdesc_raw), pending, unlinked)
            print(
                f"  -> {len(pending)} pending / {len(unlinked)} unlinked dataset(s) "
                "— noting them in the product description.",
                file=sys.stderr,
            )
        else:
            print(
                f"  -> {len(pending)} pending / {len(unlinked)} unlinked dataset(s) "
                "(description not owned by this caller).",
                file=sys.stderr,
            )

    if not _create_or_update_data_product(
        pid, pname, pdesc_raw if has_description else None, dom, dp_u
    ):
        return

    # Full-overwrite against the YAML-registered set (not just this run's assignable
    # URNs): a transient ownership lookup must not treat a still-declared table as stale.
    # Skip prune only when this run resolved zero registered URNs — wiping existing
    # links would destroy a previous successful attach because tables are still pending
    # DataHub ingestion. (batchSetDataProduct only adds links.)
    if registered or (is_metric and not pending and not unlinked):
        _prune_stale_assets(dp_u, registered)

    if not urns:
        if is_metric:
            # Metric product — owns no base tables; sources surface via golden-query subjects.
            print(
                "  -> metric product: no reference assets linked "
                "(add Trino tables and/or Superset URNs in ## Superset Golden Assets)."
            )
        else:
            print(
                f"  -> 0 datasets linked; {len(pending)} pending DataHub ingestion, "
                f"{len(unlinked)} not assigned this run "
                "(product is still published)."
            )
        return

    ln = _post(
        _SET_DATA_PRODUCT_ASSETS,
        {"input": {"dataProductUrn": dp_u, "resourceUrns": urns}},
    )
    if ln is None:
        _fail("curated.batchSetDataProduct", "mutation failed")
        return
    _ok(
        f"Linked {len(urns)} datasets"
        + (f" ({len(pending)} pending)" if pending else "")
    )


def curated_push_documentation_link(cfg: dict[str, Any]) -> None:
    print("\n[2/13] Documentation link...")
    dl = cfg.get("documentation_link")
    if not isinstance(dl, dict) or not dl.get("url") or not dl.get("label"):
        print("  -> skipping documentation_link")
        return
    dp_u = _data_product_urn(str(cfg["data_product_id"]))
    root = _graphql_root(
        _ADD_LINK,
        {
            "input": {
                "linkUrl": str(dl["url"]),
                "label": str(dl["label"]),
                "resourceUrn": dp_u,
            },
        },
    )
    errs = (root or {}).get("errors") or []
    data_g = (root or {}).get("data") if not errs else {}
    if data_g and data_g.get("addLink") is not None:
        _ok("Linked documentation")
    elif errs and _errors_indicate_already_exists(errs):
        _ok("Documentation link (already present)")
    else:
        _fail(
            "curated.addLink (documentation)",
            json.dumps(root, default=str),
        )


def curated_push_glossary_terms(cfg: dict[str, Any]) -> None:
    """Create glossary terms declared in the YAML and wire any related-term relationships.

    Skips the step gracefully when the YAML has no ``glossary_terms`` block so that
    existing configs keep working without any changes.

    After terms are created / verified the function attaches them to the Data Product
    via ``batchAddTerms``.
    """
    print("\n[3/13] Glossary terms...")
    gt_block = cfg.get("glossary_terms")
    if not isinstance(gt_block, dict) or not gt_block.get("terms"):
        print("  -> no glossary_terms block — skipping")
        return

    parent_node = (
        str(gt_block.get("parent_node_urn") or "").strip()
        or cfg.get("domain_urn")
        or _FALLBACK_GLOSSARY_PARENT_NODE_URN
    )
    terms = gt_block["terms"] if isinstance(gt_block["terms"], list) else []
    created_urns: list[str] = []

    for term in terms:
        if not isinstance(term, dict):
            continue
        term_id = str(term.get("id") or "").strip()
        label = str(term.get("name") or term_id)
        if not term_id:
            _fail("curated.glossaryTerm", f"term entry missing 'id': {term}")
            continue

        resolved_urn = _resolve_glossary_term_urn(term_id, label)
        if resolved_urn:
            print(f"  \u2192 {label}: already in catalog ({resolved_urn})")
        else:
            payload: dict[str, Any] = {
                "id": term_id,
                "name": label,
                "description": str(term.get("description") or ""),
            }
            if parent_node:
                payload["parentNode"] = parent_node

            root = _graphql_root(_CREATE_GLOSSARY_TERM, {"input": payload})
            errs = (root or {}).get("errors") or []
            data = (root or {}).get("data") if not errs else {}
            if data.get("createGlossaryTerm"):
                _ok(f"{label} ({data['createGlossaryTerm']})")
            elif errs and _errors_indicate_already_exists(errs):
                print(
                    f"  \u2192 {label}: create reported duplicate — resolving catalog URN"
                )
            else:
                _fail(label, f"unexpected response: {data}")
                continue

            resolved_urn = _resolve_glossary_term_urn(term_id, label)

        if not resolved_urn:
            _fail(
                label,
                f"glossary term id {term_id!r} not found in catalog "
                f"and name {label!r} could not be resolved",
            )
            continue

        rt = term.get("related_terms") or []
        if rt:
            _push_term_related_terms(resolved_urn, rt)

        created_urns.append(resolved_urn)

    attach_urns = _filter_existing_glossary_term_urns(created_urns)
    if not attach_urns:
        if created_urns:
            _fail(
                "curated.batchAddTerms",
                "no resolvable glossary term URNs to attach",
            )
        return

    dp_u = _data_product_urn(str(cfg["data_product_id"]))
    root = _graphql_root(
        _BATCH_ADD_TERMS,
        {
            "input": {
                "termUrns": attach_urns,
                "resources": [{"resourceUrn": dp_u}],
            }
        },
    )
    errs = (root or {}).get("errors") or []
    data = (root or {}).get("data") if not errs else {}
    if data and data.get("batchAddTerms"):
        _ok(f"Attached {len(attach_urns)} glossary term(s) to DataProduct")
    elif errs and _errors_indicate_already_exists(errs):
        _ok("Glossary terms on DataProduct (already attached)")
    else:
        _fail("curated.batchAddTerms", json.dumps(root, default=str))


def _curated_extra_query_discovery_urls(cfg: dict[str, Any]) -> list[str]:
    """Discovery deep-links for queries matching any golden query's name — minus the
    keeper URNs (every golden query's stable_urn is a keeper)."""
    gqs = _get_all_golden_queries(cfg)
    keepers = {str(gq.get("stable_urn") or "").strip() for gq in gqs}
    name_frags = {str(gq.get("name") or "").strip() for gq in gqs if gq.get("name")}
    urls: set[str] = set()
    ui_base = DATAHUB_UI_ORIGIN.rstrip("/")
    for frag in name_frags:
        blob = _post(_SEARCH_QUERIES, {"frag": frag})
        if blob is None:
            continue
        rs = ((blob.get("search") or {}).get("searchResults")) or []
        for row in rs:
            ent_u = (((row.get("entity") or {}).get("urn")) or "").strip()
            if not ent_u.startswith("urn:li:query:"):
                continue
            if ent_u in keepers:
                continue
            urls.add(f"{ui_base}/query/{ent_u}")
    return sorted(urls)


def curated_purge_discovery_links(cfg: dict[str, Any]) -> None:
    print("\n[4/13] Purge golden-query deep links...")
    gqs = _get_all_golden_queries(cfg)
    dp_u = _data_product_urn(str(cfg["data_product_id"]))
    ui_base = DATAHUB_UI_ORIGIN.rstrip("/")
    targets = {
        f"{ui_base}/query/{str(gq['stable_urn']).strip()}"
        for gq in gqs
        if gq.get("stable_urn")
    }
    targets.update(_curated_extra_query_discovery_urls(cfg))
    yaml_extra = cfg.get("extra_discovery_link_urls_remove") or []
    if isinstance(yaml_extra, list):
        targets.update(str(u) for u in yaml_extra)
    for url in sorted(targets):
        root = _graphql_root(
            _REMOVE_LINK,
            {"input": {"linkUrl": url, "resourceUrn": dp_u}},
        )
        errs = (root or {}).get("errors") or []
        if errs:
            treat_ok = any(
                needle in ((err_item.get("message") or "").lower())
                for err_item in errs
                for needle in ("not found", "does not exist", "unknown")
            )
            if not treat_ok:
                _fail(
                    f"removeLink curated [{url}]",
                    json.dumps(root, default=str),
                )
        else:
            _ok("Removed golden-query Summary URL (if present)")


def _curated_push_one_golden_query(
    gq: dict[str, Any], fallback_subject_urns: Optional[list[str]] = None
) -> Optional[str]:
    """Create/upsert one golden Query entity. Returns its URN, or None on failure.

    Prefers a stable-URN REST upsert (idempotent); falls back to GraphQL ``createQuery``.
    """
    name = str(gq["name"])
    desc_text = str(gq.get("description") or name).strip()
    sql_txt = str(gq.get("sql") or "").strip()
    stable_urn = str(gq.get("stable_urn") or "").strip()
    # Check existence first: an already-published query must stay in the sidebar
    # even when its YAML subjects are temporarily missing (authoring error).
    if stable_urn and _query_exists(stable_urn):
        _ok(f"Query already exists at {stable_urn}")
        return stable_urn

    subj = _golden_query_subject_urns(gq, fallback_subject_urns)
    if not subj:
        _fail(f"curated.goldenQuery [{name}]", "no valid subjects — new query skipped")
        return None

    if stable_urn and _ingest_query_at_urn(stable_urn, name, desc_text, sql_txt, subj):
        _ok(f"Upserted Query at {stable_urn}")
        return stable_urn

    root = _graphql_root(
        _CREATE_QUERY,
        {
            "input": {
                "properties": {
                    "name": name,
                    "description": desc_text or name,
                    "statement": {"value": sql_txt, "language": "SQL"},
                },
                "subjects": [{"datasetUrn": u} for u in sorted(subj)],
            },
        },
    )
    errs = (root or {}).get("errors") or []
    data_n = (root or {}).get("data") if not errs else {}
    if not errs:
        cq_blob = data_n.get("createQuery") or {}
        urn_c = cq_blob.get("urn") if isinstance(cq_blob, dict) else None
        if urn_c:
            if stable_urn and urn_c != stable_urn:
                print(
                    f"  ! createQuery returned {urn_c} but YAML stable_urn is "
                    f"{stable_urn}; sidebar will use the returned URN",
                    file=sys.stderr,
                )
            _ok(f"Created Query {urn_c}")
            return str(urn_c)
    if errs and _errors_indicate_already_exists(errs):
        print(f"  -> createQuery duplicate for {name!r} — using stable_urn")
        return stable_urn or None
    _fail(f"curated.createQuery [{name}]", json.dumps({"errors": errs, "data": data_n}))
    return None


def _product_subject_pool(cfg: dict[str, Any], gqs: list[dict[str, Any]]) -> list[str]:
    """Product-wide subject fallback: the product's own resolved datasets, plus every real
    table referenced across all its golden-query SQL. Used for golden queries whose own SQL
    references only a shared CTE (e.g. metric docs with a base-CTE + swapped final SELECT).
    """
    pool: list[str] = []
    try:
        for u in _curated_data_product_asset_urns(cfg):
            if u not in pool:
                pool.append(u)
    except SystemExit:
        # Non-metric product with no `datasets` would raise here; the pool simply falls
        # back to whatever the golden-query SQL references.
        pass
    for gq in gqs:
        for u in _subject_urns_from_sql(str(gq.get("sql") or "")):
            if u not in pool:
                pool.append(u)
    return pool


def curated_push_all_golden_queries(cfg: dict[str, Any]) -> list[str]:
    """Create every golden query and return the URNs that landed (for the sidebar).

    Partial-failure policy: a failed query is logged via ``_fail`` (non-zero exit) but does
    NOT abort — successful queries still publish and their URNs feed the sidebar, so one bad
    SQL block cannot wipe the rest.
    """
    gqs = _get_all_golden_queries(cfg)
    print(f"\n[5/13] Golden Query entities ({len(gqs)})...")
    if not gqs:
        print("  -> no golden queries in YAML — skipping")
        return []
    fallback_pool = _product_subject_pool(cfg, gqs)
    urns: list[str] = []
    for gq in gqs:
        urn = _curated_push_one_golden_query(gq, fallback_pool)
        if urn and urn not in urns:
            urns.append(urn)
    return urns


def curated_push_sidebar_struct_props(
    cfg: dict[str, Any], query_urns: list[str]
) -> None:
    print("\n[6/13] Sidebar structured property...")
    spec_sp = cfg.get("structured_property")
    if not isinstance(spec_sp, dict) or not spec_sp.get("qualified_name"):
        raise SystemExit("`structured_property.qualified_name` is required")

    pid = str(cfg["data_product_id"])
    dp_u = _data_product_urn(pid)
    q_name = str(spec_sp["qualified_name"])

    keeper_qs = [u for u in query_urns if str(u or "").strip()]
    if not keeper_qs:
        print("  -> no golden-query URNs to pin — skipping sidebar upsert")
        return

    raw_legacy = spec_sp.get("legacy_qualified_names_to_drop") or []
    legacy_skip = frozenset(
        structured_property_urn(str(q_str).strip())
        for q_str in (raw_legacy if isinstance(raw_legacy, list) else [])
        if str(q_str).strip()
    )

    ensure_dp_golden_struct_property(q_name)
    merged_blob = _merged_dp_structured_props(
        dp_u,
        golden_sp_qname=q_name,
        golden_query_urn_vals=keeper_qs,
        legacy_skip_urns=legacy_skip,
    )
    if merged_blob is None:
        _fail(
            "curated.upsertStructuredProperties",
            "merge aborted (see stderr)",
        )
        return

    lifecycle_stage = str(cfg.get("lifecycle_stage") or "").strip().lower()
    if lifecycle_stage:
        lifecycle_qname = "br.com.quintoandar.datahub.data_product.lifecycle_stage"
        lifecycle_sp_urn = structured_property_urn(lifecycle_qname)
        merged_blob = [
            row
            for row in merged_blob
            if row.get("structuredPropertyUrn") != lifecycle_sp_urn
        ]
        merged_blob.append(
            {
                "structuredPropertyUrn": lifecycle_sp_urn,
                "values": [{"stringValue": lifecycle_stage}],
            }
        )

    upl = _post(
        _UPSERT_STRUCTURED_PROPERTIES,
        {
            "input": {
                "assetUrn": dp_u,
                "structuredPropertyInputParams": merged_blob,
            },
        },
    )
    if upl is None or upl.get("upsertStructuredProperties") is None:
        _fail("curated.upsertStructuredProperties", repr(upl))
        return
    _ok(f"Upserted {len(merged_blob)} structured-prop bucket(s)")

    # Excluding the legacy SP from the merge above stops it being re-asserted, but the aspect
    # still lingers on the entity — upsert never deletes omitted keys. Drop it outright so a
    # republish fully overwrites: only the current data_product.golden_query SP remains.
    _drop_legacy_structured_properties(dp_u, legacy_skip)


_REMOVE_STRUCTURED_PROPERTIES = """
mutation RemoveStructuredProperties($input: RemoveStructuredPropertiesInput!) {
  removeStructuredProperties(input: $input) {
    properties { structuredProperty { urn } }
  }
}
"""


def _drop_legacy_structured_properties(
    dp_urn: str, legacy_sp_urns: frozenset[str]
) -> None:
    """Delete legacy ``*_qualified_names_to_drop`` structured-property aspects from the product.

    Non-fatal: removing an absent SP is a no-op on most DataHub builds; any error is logged
    softly rather than failing the publish (the sidebar already shows the current SP)."""
    if not legacy_sp_urns:
        return
    root = _graphql_root(
        _REMOVE_STRUCTURED_PROPERTIES,
        {
            "input": {
                "assetUrn": dp_urn,
                "structuredPropertyUrns": sorted(legacy_sp_urns),
            }
        },
    )
    if root is None:
        print(
            "  ! removeStructuredProperties HTTP failure — legacy SP(s) left in place",
            file=sys.stderr,
        )
        return
    errs = root.get("errors") or []
    if errs:
        print(
            f"  -> legacy SP removal note (likely already absent): "
            f"{json.dumps(errs)[:200]}",
            file=sys.stderr,
        )
        return
    _ok(f"Dropped {len(legacy_sp_urns)} legacy structured propert(y/ies)")


def curated_refresh_dataset_assets(cfg: dict[str, Any]) -> None:
    print("\n[7/13] Re-affirm dataset-only memberships...")
    dp_u = _data_product_urn(str(cfg["data_product_id"]))
    urns_r = _filter_assignable_urns(
        _filter_registered_dataset_urns(_curated_data_product_asset_urns(cfg)), dp_u
    )
    if not urns_r:
        if _is_metric_product(cfg):
            print(
                "  -> metric product: no reference assets to re-affirm "
                "(Trino tables / Superset URNs may be pending DataHub ingestion)."
            )
            return
        # Tables may not yet be ingested into DataHub (handled gracefully in step [1/13]).
        # Log a warning but do not fail — the description already notes the pending tables.
        print(
            "  ⚠ no DataHub-registered datasets to re-affirm — tables may still be "
            "pending ingestion (noted in product description).",
            file=sys.stderr,
        )
        return
    ref = _post(
        _SET_DATA_PRODUCT_ASSETS,
        {
            "input": {
                "dataProductUrn": dp_u,
                "resourceUrns": urns_r,
            },
        },
    )
    if ref is None:
        _fail("curated.datasets.refresh", "batchSet returned None")
        return
    _ok(f"Pinned {len(urns_r)} datasets")


# ---------------------------------------------------------------------------
# Shared SP upsert helper (used by mutations 8, 9, 10)
# ---------------------------------------------------------------------------


def _upsert_sp_on_data_product(
    dp_u: str,
    sp_urn: str,
    values: list[dict[str, Any]],
    step_label: str,
) -> bool:
    """Prefetch all SPs on a data product, replace the target SP, and upsert the merged set."""
    our_row: dict[str, Any] = {"structuredPropertyUrn": sp_urn, "values": values}
    fetch = _post(_FETCH_DATA_PRODUCT_STRUCTURED_PROPERTIES, {"urn": dp_u})
    if fetch is None:
        _fail(step_label, "prefetch structured properties failed")
        return False
    dp_blob = fetch.get("dataProduct")
    if dp_blob is None:
        _fail(step_label, "dataProduct returned null")
        return False
    props = ((dp_blob.get("structuredProperties") or {}).get("properties")) or []
    merged: list[dict[str, Any]] = []
    for prop in props:
        sp_blob = prop.get("structuredProperty") or {}
        sp_u = sp_blob.get("urn")
        if not sp_u or sp_u == sp_urn:
            continue
        converted = _structured_property_entry_to_value_inputs(prop)
        if converted is None:
            _fail(
                step_label,
                f"cannot round-trip structured property {sp_u} — aborting merge",
            )
            return False
        merged.append({"structuredPropertyUrn": sp_u, "values": converted})
    merged.append(our_row)
    upl = _post(
        _UPSERT_STRUCTURED_PROPERTIES,
        {"input": {"assetUrn": dp_u, "structuredPropertyInputParams": merged}},
    )
    if upl is None:
        _fail(step_label, "HTTP/network failure on upsert")
        return False
    return True


# ---------------------------------------------------------------------------
# Mutation 8 — Upstream data product relationships (structured property)
# ---------------------------------------------------------------------------

_UPSTREAM_SP_QNAME = "br.com.quintoandar.datahub.upstream_data_products"


def _ensure_upstream_sp_definition() -> bool:
    return _ensure_structured_property(
        _UPSTREAM_SP_QNAME,
        {
            "qualifiedName": _UPSTREAM_SP_QNAME,
            "id": _UPSTREAM_SP_QNAME,
            "displayName": "Upstream data products",
            "description": (
                "Data products this metric entity draws its schema and component logic from. "
                "Navigate to the upstream product for grain, tables, and join recipes."
            ),
            "valueType": STRUCTURED_PROPERTY_VALUE_TYPE_URN_POINTER,
            "typeQualifier": {
                "allowedTypes": [STRUCTURED_PROPERTY_ENTITY_TYPE_DATA_PRODUCT]
            },
            "cardinality": "MULTIPLE",
            "entityTypes": [STRUCTURED_PROPERTY_ENTITY_TYPE_DATA_PRODUCT],
            "settings": {
                "showInAssetSummary": True,
                "hideInAssetSummaryWhenEmpty": True,
                "showInSearchFilters": False,
                "isHidden": False,
                "showAsAssetBadge": False,
                "showInColumnsTable": False,
            },
        },
        "upstream_data_products",
    )


def curated_push_upstream_data_products(cfg: dict[str, Any]) -> None:
    """Wire upstream data product URNs as a structured property on the metric data product."""
    print("\n[8/13] Upstream data product relationships...")
    related = cfg.get("related_data_products")
    if not related or not isinstance(related, list):
        print("  -> no related_data_products — skipping")
        return

    upstream_urns: list[str] = []
    missing: list[str] = []
    for pid in related:
        u = _data_product_urn(str(pid).strip())
        if _data_product_exists(u):
            upstream_urns.append(u)
        else:
            missing.append(u)
            print(
                f"  ! upstream data product not found in DataHub: {u}", file=sys.stderr
            )

    if missing:
        _fail(
            "curated.upstream_data_products",
            f"{len(missing)} upstream product(s) not found — aborting to avoid overwriting a "
            f"complete stored list with a partial one: {missing}",
        )
        return
    if not upstream_urns:
        _fail(
            "curated.upstream_data_products",
            "none of the related_data_products exist in DataHub",
        )
        return

    if not _ensure_upstream_sp_definition():
        return

    dp_u = _data_product_urn(str(cfg["data_product_id"]))
    upstream_sp_urn = structured_property_urn(_UPSTREAM_SP_QNAME)
    if not _upsert_sp_on_data_product(
        dp_u,
        upstream_sp_urn,
        [{"stringValue": u} for u in upstream_urns],
        "curated.upstream_data_products",
    ):
        return
    _ok(
        f"Linked {len(upstream_urns)} upstream data product(s): {', '.join(upstream_urns)}"
    )


# ---------------------------------------------------------------------------
# Mutation 9 — Lifecycle stage (structured property)
# ---------------------------------------------------------------------------

_LIFECYCLE_SP_QNAME = "br.com.quintoandar.datahub.data_product.lifecycle_stage"
_LIFECYCLE_SP_ALLOWED_VALUES = frozenset({"draft", "review", "prod", "deprecated"})
_STRUCTURED_PROPERTY_VALUE_TYPE_STRING = "urn:li:dataType:datahub.string"


def _ensure_lifecycle_sp_definition() -> bool:
    return _ensure_structured_property(
        _LIFECYCLE_SP_QNAME,
        {
            "qualifiedName": _LIFECYCLE_SP_QNAME,
            "id": _LIFECYCLE_SP_QNAME,
            "displayName": "Lifecycle Stage",
            "description": (
                "Maturity stage of this Data Product. "
                "draft = under development; review = awaiting approval; "
                "prod = live and discoverable; deprecated = soft-deleted, no longer maintained."
            ),
            "valueType": _STRUCTURED_PROPERTY_VALUE_TYPE_STRING,
            "cardinality": "SINGLE",
            "entityTypes": [STRUCTURED_PROPERTY_ENTITY_TYPE_DATA_PRODUCT],
            "settings": {
                "showInAssetSummary": True,
                "hideInAssetSummaryWhenEmpty": True,
                "showInSearchFilters": True,
                "isHidden": False,
                "showAsAssetBadge": True,
                "showInColumnsTable": False,
            },
        },
        "lifecycle_stage",
    )


def curated_push_lifecycle_stage(cfg: dict[str, Any]) -> None:
    """Upsert the lifecycle_stage structured property on the data product."""
    print("\n[9/13] Lifecycle stage...")
    stage = str(cfg.get("lifecycle_stage") or "").strip().lower()
    if not stage:
        print(
            "  ! lifecycle_stage not set — add `lifecycle_stage: prod` (or draft/review/deprecated) to the YAML",
            file=sys.stderr,
        )
        _fail(
            "curated.lifecycle_stage",
            "lifecycle_stage is required but missing from YAML",
        )
        return
    if stage not in _LIFECYCLE_SP_ALLOWED_VALUES:
        _fail(
            "curated.lifecycle_stage",
            f"invalid value {stage!r} — allowed: {sorted(_LIFECYCLE_SP_ALLOWED_VALUES)}",
        )
        return

    if not _ensure_lifecycle_sp_definition():
        return

    dp_u = _data_product_urn(str(cfg["data_product_id"]))
    lifecycle_sp_urn = structured_property_urn(_LIFECYCLE_SP_QNAME)
    if not _upsert_sp_on_data_product(
        dp_u,
        lifecycle_sp_urn,
        [{"stringValue": stage}],
        "curated.lifecycle_stage",
    ):
        return
    _ok(f"Set lifecycle_stage = {stage!r}")


# ---------------------------------------------------------------------------
# Mutation 10 — Data product type (domain | metric)
# ---------------------------------------------------------------------------

_TYPE_SP_QNAME = "br.com.quintoandar.datahub.data_product.type"
_TYPE_SP_ALLOWED_VALUES = frozenset({"domain", "metric"})
_TYPE_SP_DEFAULT = "domain"


def _ensure_type_sp_definition() -> bool:
    return _ensure_structured_property(
        _TYPE_SP_QNAME,
        {
            "qualifiedName": _TYPE_SP_QNAME,
            "id": _TYPE_SP_QNAME,
            "displayName": "Data Product Type",
            "description": (
                "Classification of this Data Product. "
                "domain = domain entity / schema reference; "
                "metric = official calculated metric with a golden query."
            ),
            "valueType": _STRUCTURED_PROPERTY_VALUE_TYPE_STRING,
            "cardinality": "SINGLE",
            "entityTypes": [STRUCTURED_PROPERTY_ENTITY_TYPE_DATA_PRODUCT],
            "settings": {
                "showInAssetSummary": True,
                "hideInAssetSummaryWhenEmpty": True,
                "showInSearchFilters": True,
                "isHidden": False,
                "showAsAssetBadge": True,
                "showInColumnsTable": False,
            },
        },
        "data_product.type",
    )


def curated_push_data_product_type(cfg: dict[str, Any]) -> None:
    """Upsert the data_product.type structured property; defaults to 'domain' if not set."""
    print("\n[10/13] Data product type...")
    dp_type = str(cfg.get("data_product_type") or _TYPE_SP_DEFAULT).strip().lower()
    if dp_type not in _TYPE_SP_ALLOWED_VALUES:
        _fail(
            "curated.data_product_type",
            f"invalid value {dp_type!r} — allowed: {sorted(_TYPE_SP_ALLOWED_VALUES)}",
        )
        return

    if not _ensure_type_sp_definition():
        return

    dp_u = _data_product_urn(str(cfg["data_product_id"]))
    type_sp_urn = structured_property_urn(_TYPE_SP_QNAME)
    if not _upsert_sp_on_data_product(
        dp_u,
        type_sp_urn,
        [{"stringValue": dp_type}],
        "curated.data_product_type",
    ):
        return
    _ok(f"Set data_product_type = {dp_type!r}")


# ---------------------------------------------------------------------------
# Mutation 11 — Owners (Data Owner / Data Steward → DataHub ownership aspect)
# ---------------------------------------------------------------------------

# Maps the two YAML roles to DataHub's built-in system ownership types. Data Owner is
# the accountable party (Business Owner); Data Steward maintains the entity day-to-day.
_OWNER_ROLE_TO_OWNERSHIP_TYPE_URN: dict[str, str] = {
    "data_owner": "urn:li:ownershipType:__system__business_owner",
    "data_steward": "urn:li:ownershipType:__system__data_steward",
}
_MANAGED_OWNERSHIP_TYPE_URNS = frozenset(_OWNER_ROLE_TO_OWNERSHIP_TYPE_URN.values())

_GET_DATA_PRODUCT_OWNERS = """
query GetDataProductOwners($urn: String!) {
  dataProduct(urn: $urn) {
    ownership {
      owners {
        owner {
          ... on CorpUser { urn }
          ... on CorpGroup { urn }
        }
        ownershipType { urn }
      }
    }
  }
}
"""

_BATCH_ADD_OWNERS = """
mutation BatchAddOwners($input: BatchAddOwnersInput!) {
  batchAddOwners(input: $input)
}
"""

_REMOVE_OWNER = """
mutation RemoveOwner($input: RemoveOwnerInput!) {
  removeOwner(input: $input)
}
"""


def _corpuser_urn(email: str) -> str:
    """QuintoAndar's DataHub keys CorpUsers by full email (matches metadata ``owner:``)."""
    return f"urn:li:corpuser:{email.strip()}"


def _display_name_from_email(email: str) -> str:
    """``felipe.abreu@quintoandar.com.br`` → ``Felipe Abreu`` (best-effort stub label)."""
    local = email.strip().split("@", 1)[0]
    parts = [p for p in re.split(r"[._-]+", local) if p]
    return " ".join(p.capitalize() for p in parts) or local


def _corpuser_exists(owner_urn: str) -> Optional[bool]:
    """Tri-state existence check: True / False / None (transient HTTP or GraphQL failure).

    None must NOT be treated as "missing" — otherwise a transient blip would trigger a
    stub UPSERT that clobbers a real user's info (displayName / active).
    """
    data = _post(_ENTITY_EXISTS, {"urn": owner_urn})
    if data is None:
        return None
    return bool(data.get("entityExists"))


def _provision_corpuser_stub(email: str, owner_urn: str) -> bool:
    """Create a minimal CorpUser so an accountable owner who never used DataHub still
    appears (and can be assigned ownership). Enriched later if the person logs in or the
    identity directory is ingested. Only called when the user is confirmed missing.
    """
    aspect = {
        "active": True,
        "displayName": _display_name_from_email(email),
        "email": email,
    }
    ok, detail = _gms_ingest_proposal(
        {
            "proposal": {
                "entityType": "corpuser",
                "entityUrn": owner_urn,
                "changeType": "UPSERT",
                "aspectName": "corpUserInfo",
                "aspect": {
                    "contentType": "application/json",
                    "value": json.dumps(aspect),
                },
            }
        }
    )
    if not ok:
        print(
            f"    [DEBUG] corpUserInfo provisioning failed: {detail}", file=sys.stderr
        )
    return ok


def _declared_owner_triples(owners_block: dict[str, Any]) -> list[tuple[str, str, str]]:
    """Flatten the YAML owners block into ``(email, corpuser_urn, ownership_type_urn)``."""
    triples: list[tuple[str, str, str]] = []
    seen: set[tuple[str, str]] = set()
    for role, type_urn in _OWNER_ROLE_TO_OWNERSHIP_TYPE_URN.items():
        emails = owners_block.get(role) or []
        if not isinstance(emails, list):
            continue
        for email in emails:
            email = str(email).strip()
            if not email:
                continue
            key = (_corpuser_urn(email), type_urn)
            if key not in seen:
                seen.add(key)
                triples.append((email, key[0], type_urn))
    return triples


def _fetch_current_managed_owner_pairs(dp_urn: str) -> Optional[set[tuple[str, str]]]:
    """Current ``(owner_urn, type_urn)`` pairs on the DP, limited to types we manage.

    Returns ``None`` on HTTP/GraphQL failure so callers can fail-closed instead of
    treating a transient error as "no owners" (which would wrongly remove everyone).
    """
    data = _post(_GET_DATA_PRODUCT_OWNERS, {"urn": dp_urn})
    if data is None:
        return None
    ownership = (_graphql_field(data, "dataProduct").get("ownership")) or {}
    pairs: set[tuple[str, str]] = set()
    for entry in ownership.get("owners") or []:
        owner_urn = str(((entry or {}).get("owner") or {}).get("urn") or "").strip()
        type_urn = str(
            ((entry or {}).get("ownershipType") or {}).get("urn") or ""
        ).strip()
        if owner_urn and type_urn in _MANAGED_OWNERSHIP_TYPE_URNS:
            pairs.add((owner_urn, type_urn))
    return pairs


def curated_push_owners(cfg: dict[str, Any]) -> None:
    """Declaratively sync Data Owner / Data Steward emails onto the Data Product.

    - Adds declared owners that are not present yet. An owner who is accountable but has
      never used DataHub (e.g. a director) won't exist as a CorpUser, so we auto-provision
      a minimal CorpUser stub first — ownership is about accountability, not tool access.
    - Removes owners of the two managed types that are no longer declared in the MD
      (owners of other types, e.g. a manually-added Technical Owner, are left untouched).
    - A declared owner is never used to justify a removal even if its lookup/provisioning
      fails — a transient miss must not drop a still-declared owner.
    """
    print("\n[11/13] Owners (Data Owner / Data Steward)...")
    owners_block = cfg.get("owners")
    if not isinstance(owners_block, dict):
        print("  -> no owners block — skipping")
        return

    declared = _declared_owner_triples(owners_block)
    declared_set = {(owner_urn, type_urn) for _, owner_urn, type_urn in declared}
    dp_u = _data_product_urn(str(cfg["data_product_id"]))

    current = _fetch_current_managed_owner_pairs(dp_u)
    if current is None:
        _fail(
            "curated.owners", "prefetch current owners failed — skipping to stay safe"
        )
        return

    resolved: list[tuple[str, str]] = []
    for email, owner_urn, type_urn in declared:
        exists = _corpuser_exists(owner_urn)
        if exists is None:
            print(
                f"  ! existence check failed for {owner_urn} (transient) — "
                "skipping this owner for now (will retry next run)",
                file=sys.stderr,
            )
            continue
        if not exists:
            if _provision_corpuser_stub(email, owner_urn):
                print(f"  \u2192 provisioned CorpUser stub for {email}")
            else:
                print(
                    f"  ! could not provision CorpUser for {email} — skipping this owner",
                    file=sys.stderr,
                )
                continue
        resolved.append((owner_urn, type_urn))

    to_add = [pair for pair in resolved if pair not in current]
    to_remove = [pair for pair in current if pair not in declared_set]

    if to_add:
        added = _post(
            _BATCH_ADD_OWNERS,
            {
                "input": {
                    "owners": [
                        {
                            "ownerUrn": owner_urn,
                            "ownerEntityType": "CORP_USER",
                            "ownershipTypeUrn": type_urn,
                        }
                        for owner_urn, type_urn in to_add
                    ],
                    "resources": [{"resourceUrn": dp_u}],
                }
            },
        )
        if added and added.get("batchAddOwners"):
            _ok(f"Added {len(to_add)} owner(s)")
        else:
            _fail("curated.owners.add", f"unexpected response: {added}")
            return

    for owner_urn, type_urn in to_remove:
        removed = _post(
            _REMOVE_OWNER,
            {
                "input": {
                    "ownerUrn": owner_urn,
                    "resourceUrn": dp_u,
                    "ownershipTypeUrn": type_urn,
                }
            },
        )
        if removed and removed.get("removeOwner") is not False:
            _ok(f"Removed owner no longer declared: {owner_urn}")
        else:
            _fail(
                "curated.owners.remove",
                f"unexpected response for {owner_urn}: {removed}",
            )
            return

    if not to_add and not to_remove:
        _ok(f"Owners already in sync ({len(declared_set)} declared)")


# ---------------------------------------------------------------------------
# Mutation 12 — MBR membership (data_product.mbr / .mbr_category, metric-only)
# ---------------------------------------------------------------------------

_MBR_SP_QNAME = "br.com.quintoandar.datahub.data_product.mbr"
_MBR_CATEGORY_SP_QNAME = "br.com.quintoandar.datahub.data_product.mbr_category"

# DataHub allows only ONE badge structured property per entity type, and
# data_product.type already claims it — every curated multi-valued property below
# therefore stays off the badge while remaining a search filter.
_MULTI_VALUE_SP_SETTINGS = {
    "showInAssetSummary": True,
    "hideInAssetSummaryWhenEmpty": True,
    "showInSearchFilters": True,
    "isHidden": False,
    "showAsAssetBadge": False,
    "showInColumnsTable": False,
}


def _ensure_multi_value_sp_definition(
    qname: str, display_name: str, description: str, label: str
) -> bool:
    return _ensure_structured_property(
        qname,
        {
            "qualifiedName": qname,
            "id": qname,
            "displayName": display_name,
            "description": description,
            "valueType": _STRUCTURED_PROPERTY_VALUE_TYPE_STRING,
            "cardinality": "MULTIPLE",
            "entityTypes": [STRUCTURED_PROPERTY_ENTITY_TYPE_DATA_PRODUCT],
            "settings": dict(_MULTI_VALUE_SP_SETTINGS),
        },
        label,
    )


def _sync_multi_value_sp(
    dp_urn: str, qname: str, values: list[str], label: str
) -> bool:
    """Upsert a multi-valued SP, or drop the aspect entirely when ``values`` is empty.

    The empty case is the flip-off half of the declarative contract: a document that
    dropped the section must not keep publishing a stale value in DataHub.
    """
    sp_urn = structured_property_urn(qname)
    if not values:
        _drop_legacy_structured_properties(dp_urn, frozenset({sp_urn}))
        return True
    return _upsert_sp_on_data_product(
        dp_urn,
        sp_urn,
        [{"stringValue": value} for value in values],
        label,
    )


def _dedup_preserving_order(values: list[str]) -> list[str]:
    """De-duplicate case-insensitively while keeping the first spelling and its order."""
    out: list[str] = []
    seen: set[str] = set()
    for value in values:
        cleaned = str(value).strip()
        if cleaned and cleaned.lower() not in seen:
            seen.add(cleaned.lower())
            out.append(cleaned)
    return out


def _mbr_entries(cfg: dict[str, Any]) -> tuple[list[str], list[str]]:
    """Split the ``mbr:`` spec block into MBR names and MBR categories.

    Accepts both shapes: the current ``- name: X`` / ``category: Y`` mappings and the
    legacy plain-string list, so a spec generated before the ``## MBR`` format change
    still publishes its membership (with no category).
    """
    raw = cfg.get("mbr")
    if isinstance(raw, str):
        raw = [raw]
    names: list[str] = []
    categories: list[str] = []
    for item in raw or []:
        if isinstance(item, dict):
            names.append(str(item.get("name") or "").strip())
            categories.append(str(item.get("category") or "").strip())
        else:
            names.append(str(item).strip())
    return _dedup_preserving_order(names), _dedup_preserving_order(categories)


def _ensure_mbr_sp_definition() -> bool:
    return _ensure_multi_value_sp_definition(
        _MBR_SP_QNAME,
        "MBR",
        (
            "Monthly Business Review(s) this metric Data Product's metrics belong to. "
            "Multi-valued: a metric may feed more than one MBR. Present only on metric "
            "Data Products that participate in an MBR; absent = not part of any MBR."
        ),
        "data_product.mbr",
    )


def _ensure_mbr_category_sp_definition() -> bool:
    return _ensure_multi_value_sp_definition(
        _MBR_CATEGORY_SP_QNAME,
        "MBR Category",
        (
            "Category this metric Data Product occupies inside its Monthly Business "
            "Review agenda. Multi-valued: a metric feeding several MBRs may sit in a "
            "different category in each. Absent = no category declared."
        ),
        "data_product.mbr_category",
    )


def curated_push_mbr(cfg: dict[str, Any]) -> None:
    """Declaratively sync the MBR structured properties (metric DPs only).

    Multi-valued: a metric may belong to several MBRs, each with its own category.
    Absent/empty on a metric product clears any previously-set value (flip-off), so
    removing the ``## MBR`` section from the Markdown removes the membership in DataHub.
    Non-metric products are skipped — MBR is a metric-only concept.
    """
    print("\n[12/13] MBR membership...")
    is_metric = str(cfg.get("data_product_type") or "").strip().lower() == "metric"
    if not is_metric:
        print("  -> not a metric data product — skipping")
        return

    mbrs, categories = _mbr_entries(cfg)

    if not _ensure_mbr_sp_definition() or not _ensure_mbr_category_sp_definition():
        return

    dp_u = _data_product_urn(str(cfg["data_product_id"]))

    if not _sync_multi_value_sp(dp_u, _MBR_SP_QNAME, mbrs, "curated.mbr"):
        return
    if not _sync_multi_value_sp(
        dp_u, _MBR_CATEGORY_SP_QNAME, categories, "curated.mbr_category"
    ):
        return

    if not mbrs:
        _ok("No MBR declared — cleared any previous value")
        return
    _ok(f"Set mbr = {mbrs!r}, mbr_category = {categories!r}")


# ---------------------------------------------------------------------------
# Mutation 13 — Metric catalog (data_product.metrics / .metric_type, metric-only)
# ---------------------------------------------------------------------------

_METRICS_SP_QNAME = "br.com.quintoandar.datahub.data_product.metrics"
_METRIC_TYPE_SP_QNAME = "br.com.quintoandar.datahub.data_product.metric_type"


def _ensure_metrics_sp_definition() -> bool:
    return _ensure_multi_value_sp_definition(
        _METRICS_SP_QNAME,
        "Metrics",
        (
            "Official metrics defined by this metric Data Product, as named in its "
            "`## Catalog` section. Multi-valued: a document may define a family of "
            "related metrics. Absent = no catalog declared."
        ),
        "data_product.metrics",
    )


def _ensure_metric_type_sp_definition() -> bool:
    return _ensure_multi_value_sp_definition(
        _METRIC_TYPE_SP_QNAME,
        "Metric Type",
        (
            "How this Data Product's metrics are used by the business: OKR = carries a "
            "period goal tracked as an objective; Health Metric = monitored for "
            "operational health with no goal of its own. Multi-valued: a document "
            "defining several metrics may mix both."
        ),
        "data_product.metric_type",
    )


def curated_push_catalog(cfg: dict[str, Any]) -> None:
    """Declaratively sync the metric catalog structured property (metric DPs only).

    ``metrics`` carries one value per official metric named in ``## Catalog``, with its
    OKR / Health Metric classification embedded in the value itself (e.g.
    ``"NPS True (OKR)"``). Every row is guaranteed to carry a type by the time it
    reaches here — the CI/CD publish script (``_validate_catalog_types`` in
    ``generate_and_push_datahub_entities.py``) refuses to publish a metric with no
    recognized type — so this is a straight 1:1 rendering, not a best-effort fallback.

    The legacy ``data_product.metric_type`` property (a separately de-duplicated list
    with no positional link back to ``metrics``) is actively cleared here rather than
    just abandoned, so Data Products published before this change don't keep showing a
    stale, unpaired type list next to the new self-describing ``metrics`` values. The
    clear runs *after* the ``metrics`` upsert succeeds: dropping it first would leave a
    product whose upsert then failed with plain, unclassified metric names and no type
    list at all until the next successful publish.

    An absent or empty catalog clears both properties, keeping DataHub in lockstep with
    the Markdown.
    """
    print("\n[13/13] Metric catalog...")
    is_metric = str(cfg.get("data_product_type") or "").strip().lower() == "metric"
    if not is_metric:
        print("  -> not a metric data product — skipping")
        return

    raw = cfg.get("catalog") or []
    entries = _dedup_preserving_order(
        [
            f"{row['name']} ({row['type']})" if row.get("type") else str(row["name"])
            for row in raw
            if isinstance(row, dict) and row.get("name")
        ]
    )

    if not _ensure_metrics_sp_definition():
        return

    dp_u = _data_product_urn(str(cfg["data_product_id"]))

    if not _sync_multi_value_sp(dp_u, _METRICS_SP_QNAME, entries, "curated.metrics"):
        return

    # Deprecated in favor of embedding the type in each `metrics` value above — drop any
    # value left over from before this change, now that the new values are in place.
    if _ensure_metric_type_sp_definition():
        _sync_multi_value_sp(dp_u, _METRIC_TYPE_SP_QNAME, [], "curated.metric_type")

    if not entries:
        _ok("No catalog declared — cleared any previous value")
        return
    _ok(f"Set metrics = {entries!r}")


def run_data_product_curated_entity(spec: dict[str, Any]) -> None:
    curated_push_assets(spec)  # [1/13]
    curated_push_documentation_link(spec)  # [2/13]
    curated_push_glossary_terms(spec)  # [3/13]
    curated_purge_discovery_links(spec)  # [4/13]
    query_urns = curated_push_all_golden_queries(spec)  # [5/13]
    curated_push_sidebar_struct_props(spec, query_urns)  # [6/13]
    curated_refresh_dataset_assets(spec)  # [7/13]
    curated_push_upstream_data_products(spec)  # [8/13]
    curated_push_lifecycle_stage(spec)  # [9/13]
    curated_push_data_product_type(spec)  # [10/13]
    curated_push_owners(spec)  # [11/13]
    curated_push_mbr(spec)  # [12/13]
    curated_push_catalog(spec)  # [13/13]


def run_full_curated_datahub_bundle(spec: dict[str, Any]) -> None:
    global _ACTIVE_FULL_CURATED_BUNDLE

    bundle_id = str(spec.get("bundle_id") or "").strip()
    if not bundle_id:
        raise SystemExit(
            "full_curated_datahub_bundle presets require bundle_id "
            f"(supported: {FULL_CURATED_BUNDLE_IDS_SUPPORTED})"
        )
    bundle_mod = resolve_full_bundle_module(bundle_id)

    urns = load_curated_urns_from_spec(spec, bundle_mod.curated_urn_baseline_kwargs())
    _ACTIVE_FULL_CURATED_BUNDLE = ActiveFullCuratedBundle(
        bundle_module=bundle_mod,
        urns=urns,
    )
    BUNDLE_YAML_RUNTIME.clear()
    BUNDLE_YAML_RUNTIME["domain_urn"] = urns.domain_urn
    BUNDLE_YAML_RUNTIME["glossary_parent_node_urn"] = urns.glossary_parent_node_urn
    try:
        push_dataset_descriptions()
        push_schema_field_descriptions()
        push_glossary_terms()
        push_data_product()
        push_data_product_enrichments()
        push_golden_query()
        push_golden_query_structured_property()
    finally:
        BUNDLE_YAML_RUNTIME.clear()
        _ACTIVE_FULL_CURATED_BUNDLE = None


def _pipeline_reset_errors() -> None:
    global _errors
    _errors = []


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> None:
    if not GRAPHQL_URL:
        print(
            "ERROR: DATAHUB_GRAPHQL_URL is not set.\n"
            "  export DATAHUB_GRAPHQL_URL=https://<datahub-host>/api/graphql\n"
            "  export DATAHUB_TOKEN=<personal-access-token>",
            file=sys.stderr,
        )
        sys.exit(1)

    parser = argparse.ArgumentParser(
        description="Push DataHub curated context from YAML (spec_version: 1).",
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=DEFAULT_CONFIG_PATH,
        help=(
            "Path to *.datahub.yaml "
            "(default: reference/payments.datahub.yaml beside this script)"
        ),
    )
    ns = parser.parse_args()
    path = ns.config.resolve()

    print(f"DataHub target  : {GRAPHQL_URL}")
    print(f"Auth token       : {'set' if TOKEN else 'NOT SET (mutations may fail)'}")
    print(f"Config file      : {path}")

    if not path.exists():
        print(f"Missing config file: {path}", file=sys.stderr)
        sys.exit(1)

    bundle = load_yaml_spec(path)
    _ensure_spec_supported(bundle, path)
    kind_sel = bundle.get("kind")

    print(f"preset.kind      : {kind_sel}")

    _pipeline_reset_errors()

    try:
        if kind_sel == KIND_FULL_CURATED_DATAHUB_BUNDLE:
            run_full_curated_datahub_bundle(bundle)
        elif kind_sel == KIND_DATA_PRODUCT_CURATED_ENTITY:
            run_data_product_curated_entity(bundle)
        else:
            raise SystemExit(
                f"{path}: unsupported kind {kind_sel!r} "
                f"(need '{KIND_FULL_CURATED_DATAHUB_BUNDLE}' or "
                f"'{KIND_DATA_PRODUCT_CURATED_ENTITY}')"
            )

        print("\n" + "=" * 60)
        if _errors:
            print(f"DONE with {len(_errors)} error(s):")
            for detail in _errors:
                print(f"  {detail}")
            sys.exit(1)
        print("All mutations succeeded.")
    except SystemExit:
        raise
    except BaseException as exc:  # pragma: no cover
        print(f"ABORTED: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
