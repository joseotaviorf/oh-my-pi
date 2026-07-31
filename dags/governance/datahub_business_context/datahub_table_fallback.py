"""DataHub catalog fallback for golden-query schema validation.

When a ``schema.table`` pair is absent from repo metadata YAML, optionally probe
DataHub (read-only GraphQL) for dataset existence and ``schemaMetadata.fields``.
"""

from __future__ import annotations

import json
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from typing import Any, Callable, Optional

from golden_query_metadata_validator import MetadataSchemaClient
from golden_query_schema_validator import GoldenQuerySchemaClient

_PLATFORM_PROBE_ORDER: list[tuple[str, str]] = [
    ("trino", "hive.{schema}.{table}"),
    ("databricks", "{schema}.{table}"),
]

_ENTITY_EXISTS = """
query EntityExists($urn: String!) {
  entityExists(urn: $urn)
}
"""

_DATASET_SCHEMA = """
query DatasetSchema($urn: String!) {
  dataset(urn: $urn) {
    schemaMetadata {
      fields {
        fieldPath
      }
    }
  }
}
"""

GraphQLPost = Callable[
    [str, Optional[str], str, dict[str, Any], float],
    tuple[Optional[dict[str, Any]], str],
]


def build_urllib_graphql_post(
    graphql_url: str,
) -> GraphQLPost:
    """Return a read-only GraphQL POST callable bound to ``graphql_url``."""

    def _post(
        _url: str,
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
            headers={
                "Accept": "application/json",
                "Content-Type": "application/json",
            },
        )
        if token:
            req.add_header("Authorization", f"Bearer {token}")
        try:
            with urllib.request.urlopen(req, timeout=timeout_sec) as resp:
                if int(getattr(resp, "status", None) or resp.getcode()) != 200:
                    return None, "http_error"
                raw = resp.read()
                if not raw or not raw.strip():
                    return None, "empty_body"
                root = json.loads(raw.decode("utf-8"))
                if root.get("errors"):
                    return None, "graphql_error"
                return root.get("data") or {}, "ok"
        except (urllib.error.URLError, json.JSONDecodeError, TimeoutError, OSError):
            return None, "fetch_error"

    return _post


def _urn_candidates(schema: str, table: str) -> list[str]:
    return [
        f"urn:li:dataset:(urn:li:dataPlatform:{platform},{template.format(schema=schema, table=table)},PROD)"
        for platform, template in _PLATFORM_PROBE_ORDER
    ]


def _field_path_to_column_name(field_path: str) -> str:
    path = (field_path or "").strip()
    if not path:
        return ""
    # DataHub may use dotted paths for nested fields — golden queries reference leaf names.
    return path.split(".")[-1].lower()


@dataclass
class DataHubSchemaProbe:
    """Read-only DataHub dataset existence + schema field lookup."""

    post: GraphQLPost
    token: Optional[str]
    _urn_cache: dict[tuple[str, str], Optional[str]] = field(default_factory=dict)
    _columns_cache: dict[str, Optional[set[str]]] = field(default_factory=dict)

    def resolve_dataset_urn(self, schema: str, table: str) -> Optional[str]:
        key = (schema.strip().lower(), table.strip().lower())
        if key not in self._urn_cache:
            resolved: Optional[str] = None
            for urn in _urn_candidates(key[0], key[1]):
                data, status = self.post("", self.token, _ENTITY_EXISTS, {"urn": urn})
                if status == "ok" and data and data.get("entityExists"):
                    resolved = urn
                    break
            self._urn_cache[key] = resolved
        return self._urn_cache[key]

    def column_names_for_urn(self, urn: str) -> Optional[set[str]]:
        if urn not in self._columns_cache:
            data, status = self.post("", self.token, _DATASET_SCHEMA, {"urn": urn})
            if status != "ok" or not data:
                self._columns_cache[urn] = None
            else:
                fields = ((data.get("dataset") or {}).get("schemaMetadata") or {}).get(
                    "fields"
                ) or []
                cols = {
                    name
                    for name in (
                        _field_path_to_column_name(str(f.get("fieldPath") or ""))
                        for f in fields
                        if isinstance(f, dict)
                    )
                    if name
                }
                self._columns_cache[urn] = cols
        return self._columns_cache[urn]

    def column_names_for_table(self, schema: str, table: str) -> Optional[set[str]]:
        urn = self.resolve_dataset_urn(schema, table)
        if not urn:
            return None
        return self.column_names_for_urn(urn)


@dataclass
class DataHubFallbackSchemaClient:
    """Metadata-first schema client with optional DataHub catalog fallback."""

    inner: MetadataSchemaClient
    probe: DataHubSchemaProbe | None = None

    def table_exists(self, schema: str, table: str) -> bool:
        if self.inner.table_exists(schema, table):
            return True
        if self.probe is None:
            return False
        return self.probe.resolve_dataset_urn(schema, table) is not None

    def column_names_for_table(self, schema: str, table: str) -> Optional[set[str]]:
        cols = self.inner.column_names_for_table(schema, table)
        if cols is not None:
            return cols
        if self.probe is None:
            return None
        return self.probe.column_names_for_table(schema, table)

    def table_source_hint(self, schema: str, table: str) -> str:
        if self.inner.table_exists(schema, table):
            return self.inner.table_source_hint(schema, table)
        if self.probe is None:
            return self.inner.table_source_hint(schema, table)
        urn = self.probe.resolve_dataset_urn(schema, table)
        if urn:
            return f"resolved via DataHub catalog ({urn})"
        return self.inner.table_source_hint(schema, table)


def build_datahub_fallback_client(
    inner: MetadataSchemaClient,
    *,
    graphql_url: str,
    token: str,
    post: GraphQLPost | None = None,
) -> GoldenQuerySchemaClient:
    """Wrap ``inner`` with a DataHub probe when credentials are configured."""
    url = (graphql_url or "").strip()
    tok = (token or "").strip() or None
    if not url or not tok:
        return inner
    probe = DataHubSchemaProbe(post=post or build_urllib_graphql_post(url), token=tok)
    return DataHubFallbackSchemaClient(inner=inner, probe=probe)
