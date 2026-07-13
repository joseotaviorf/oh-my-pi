"""DataHub GraphQL client: URL resolution, HTTP POST, and response JSON parsing (F4, I1-02, I3)."""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from typing import Any, Mapping, NamedTuple, Optional

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.governance.fairness_assessment.constants import (
    DATAHUB_FETCH_ERROR,
    DATAHUB_HTTP_ERROR,
    DATAHUB_OWNERSHIP_TYPE_APPROVERS_URN,
    DATAHUB_SP_DATA_CONTRACT_URN,
    DATAHUB_SP_HOW_TO_REQUEST_ACCESS_URN,
    DATAHUB_URN_DIAG_OK,
)


class DatasetFairSignals(NamedTuple):
    """Parsed per-dataset DataHub signals (URN-level), rolled up to FQN by the compute layer.

    ``has_data_contract`` / ``how_to_request_access`` come from structured properties; the former
    replaces the legacy ``institutionalMemory`` label scan. ``approvers_ownership`` is True when the
    entity has an owner assigned with the ``Approvers`` ownership type. ``had_dataset`` is False when
    the GraphQL alias resolved to ``null`` (URN unknown to DataHub).
    """

    indexed_ok: bool
    has_data_contract: bool
    ownership_nonempty: bool
    upstream_total: int
    downstream_total: int
    had_dataset: bool
    how_to_request_access: bool
    approvers_ownership: bool


_EMPTY_DATASET_FAIR_SIGNALS = DatasetFairSignals(
    False, False, False, 0, 0, False, False, False
)

LOGGER = QuintoAndarLogger(__name__)

# Truncate response bodies in logs to avoid leaking large payloads / dumping noise; 500 chars is
# enough for typical GraphQL/Auth error envelopes (HTML 401, JSON ``errors`` array, etc.).
_HTTP_ERROR_BODY_MAX_CHARS = 500

# -- URL + HTTP ----------------------------------------------------------------


def resolve_datahub_graphql_url(config_service: Any) -> str:
    """GraphQL endpoint for DataHub (``POST`` with ``query`` / ``variables``).

    Resolution order:

    1. ``DATAHUB_GRAPHQL_URL`` — full URL (e.g. ``https://datahub.../api/graphql``).
    2. ``datahub_graphql_url`` from merged env YAML (``forno_conf.yml`` / ``prod_conf.yml``).
    3. ``{datahub_host}/api/graphql`` when ``datahub_host`` is set.
    """

    env = os.environ.get("DATAHUB_GRAPHQL_URL", "").strip()
    if env:
        return env.rstrip("/")
    explicit = str(config_service.configs.get("datahub_graphql_url") or "").strip()
    if explicit:
        return explicit.rstrip("/")
    host = str(config_service.configs.get("datahub_host") or "").strip().rstrip("/")
    if host:
        return f"{host}/api/graphql"
    return ""


def resolve_datahub_gms_base_url(config_service: Any) -> str:
    """Deprecated alias: GMS host URL. Prefer ``resolve_datahub_graphql_url`` for fairness checks."""

    env = os.environ.get("DATAHUB_GMS_HOST", "").strip()
    if env:
        return env
    return str(config_service.configs.get("datahub_gms_host") or "").strip()


def datahub_graphql_post(
    graphql_url: str,
    token: Optional[str],
    query: str,
    variables: Mapping[str, Any],
    timeout_sec: float = 60.0,
) -> tuple[Optional[dict[str, Any]], str]:
    """POST GraphQL body; returns (parsed JSON root dict or None, diagnostic).

    HTTP 200 can still contain GraphQL ``errors``; see DataHub docs.
    """

    payload = json.dumps({"query": query, "variables": dict(variables)}).encode("utf-8")
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
            status = int(getattr(resp, "status", None) or resp.getcode())
            if status != 200:
                LOGGER.warning(
                    f"m=datahub_graphql_post_non_200,url={graphql_url},status={status}"
                )
                return None, DATAHUB_HTTP_ERROR
            raw = resp.read()
            if not raw or not raw.strip():
                LOGGER.warning(
                    f"m=datahub_graphql_post_empty_body,url={graphql_url},status={status}"
                )
                return None, DATAHUB_FETCH_ERROR
            try:
                text = raw.decode("utf-8")
            except UnicodeDecodeError:
                LOGGER.warning(f"m=datahub_graphql_post_decode_error,url={graphql_url}")
                return None, DATAHUB_FETCH_ERROR
            try:
                root = json.loads(text)
            except json.JSONDecodeError:
                LOGGER.warning(
                    f"m=datahub_graphql_post_json_error,url={graphql_url},"
                    f"body={text[:_HTTP_ERROR_BODY_MAX_CHARS]}"
                )
                return None, DATAHUB_FETCH_ERROR
            return root, DATAHUB_URN_DIAG_OK
    except urllib.error.HTTPError as exc:
        body = ""
        try:
            body = exc.read().decode("utf-8", errors="replace")[
                :_HTTP_ERROR_BODY_MAX_CHARS
            ]
        except Exception:
            # Body may already be consumed or unreadable; status/reason are still actionable.
            pass
        LOGGER.warning(
            f"m=datahub_graphql_post_http_error,url={graphql_url},"
            f"status={exc.code},reason={exc.reason},body={body}"
        )
        return None, DATAHUB_HTTP_ERROR
    except TimeoutError as exc:
        LOGGER.warning(
            f"m=datahub_graphql_post_timeout,url={graphql_url},"
            f"timeout_sec={timeout_sec},err={exc}"
        )
        return None, DATAHUB_FETCH_ERROR
    except urllib.error.URLError as exc:
        LOGGER.warning(
            f"m=datahub_graphql_post_url_error,url={graphql_url},reason={exc.reason}"
        )
        return None, DATAHUB_FETCH_ERROR
    except OSError as exc:
        LOGGER.warning(f"m=datahub_graphql_post_os_error,url={graphql_url},err={exc}")
        return None, DATAHUB_FETCH_ERROR


# -- GraphQL / entity JSON parsing ----------------------------------------------------------------


def structured_property_has_nonempty_value(
    sp_properties: Any, target_sp_urn: str
) -> bool:
    """True if ``structuredProperties.properties`` has ``target_sp_urn`` with a non-empty value.

    A value counts as present when it is a non-blank ``stringValue`` or any ``numberValue``.
    """

    if not isinstance(sp_properties, list):
        return False
    for prop in sp_properties:
        if not isinstance(prop, dict):
            continue
        sp_def = prop.get("structuredProperty") or {}
        if not isinstance(sp_def, dict) or sp_def.get("urn") != target_sp_urn:
            continue
        for val in prop.get("values") or []:
            if not isinstance(val, dict):
                continue
            string_value = val.get("stringValue")
            if isinstance(string_value, str) and string_value.strip():
                return True
            if val.get("numberValue") is not None:
                return True
    return False


def ownership_has_type(owners_list: Any, target_ownership_type_urn: str) -> bool:
    """True if any ``ownership.owners[].ownershipType.urn`` matches ``target_ownership_type_urn``."""

    if not isinstance(owners_list, list):
        return False
    for owner in owners_list:
        if not isinstance(owner, dict):
            continue
        ownership_type = owner.get("ownershipType") or {}
        if (
            isinstance(ownership_type, dict)
            and ownership_type.get("urn") == target_ownership_type_urn
        ):
            return True
    return False


def _parse_dataset_node(ds: Any) -> DatasetFairSignals:
    """Parse a single ``dataset`` node payload into :class:`DatasetFairSignals`.

    ``had_dataset`` is False when the alias resolved to ``null`` (URN unknown to DataHub).
    """

    if not isinstance(ds, dict):
        return _EMPTY_DATASET_FAIR_SIGNALS

    exists = ds.get("exists")
    indexed_ok = bool(exists) if exists is not None else False

    owners_block = ds.get("ownership") if isinstance(ds.get("ownership"), dict) else {}
    owners_list = owners_block.get("owners") if isinstance(owners_block, dict) else None
    ownership_nonempty = bool(isinstance(owners_list, list) and len(owners_list) > 0)
    approvers_ownership = ownership_has_type(
        owners_list, DATAHUB_OWNERSHIP_TYPE_APPROVERS_URN
    )

    sp_block = ds.get("structuredProperties")
    sp_properties = sp_block.get("properties") if isinstance(sp_block, dict) else None
    has_data_contract = structured_property_has_nonempty_value(
        sp_properties, DATAHUB_SP_DATA_CONTRACT_URN
    )
    how_to_request_access = structured_property_has_nonempty_value(
        sp_properties, DATAHUB_SP_HOW_TO_REQUEST_ACCESS_URN
    )

    up_obj = ds.get("upstream") if isinstance(ds.get("upstream"), dict) else {}
    down_obj = ds.get("downstream") if isinstance(ds.get("downstream"), dict) else {}
    up_tot = up_obj.get("total")
    down_tot = down_obj.get("total")
    try:
        up_n = int(up_tot) if up_tot is not None else 0
    except (TypeError, ValueError):
        up_n = 0
    try:
        down_n = int(down_tot) if down_tot is not None else 0
    except (TypeError, ValueError):
        down_n = 0

    return DatasetFairSignals(
        indexed_ok=indexed_ok,
        has_data_contract=has_data_contract,
        ownership_nonempty=ownership_nonempty,
        upstream_total=up_n,
        downstream_total=down_n,
        had_dataset=True,
        how_to_request_access=how_to_request_access,
        approvers_ownership=approvers_ownership,
    )


def _parse_dataset_fair_signals(root: Mapping[str, Any]) -> DatasetFairSignals:
    """From single-dataset GraphQL root, return the fair-signals tuple (see ``_parse_dataset_node``)."""

    data = root.get("data")
    if not isinstance(data, dict):
        return _EMPTY_DATASET_FAIR_SIGNALS
    return _parse_dataset_node(data.get("dataset"))


# -- GraphQL batching ---------------------------------------------------------------------------
#
# Single shared selection body: identical to ``DATAHUB_DATASET_FAIR_SIGNALS_QUERY`` but parameterised
# by alias index so we can pack N datasets into one POST. Each alias costs ~10 in DataHub's GraphQL
# complexity budget, so 25 aliases ≈ 250 — well under the default ``complexityLimit`` (2000).
_DATASET_FAIR_SIGNALS_SELECTION = (
    "exists "
    "ownership { owners { ownershipType { urn } "
    "owner { ... on CorpUser { urn } ... on CorpGroup { urn } } } } "
    "upstream: lineage(input: { direction: UPSTREAM, start: 0, count: 0 }) { total } "
    "downstream: lineage(input: { direction: DOWNSTREAM, start: 0, count: 0 }) { total } "
    "structuredProperties { properties { structuredProperty { urn } "
    "values { ... on StringValue { stringValue } ... on NumberValue { numberValue } } } }"
)


def build_dataset_fair_signals_batch_query(
    urns: list[str],
) -> tuple[str, dict[str, str]]:
    """Build a single GraphQL query that fetches fair-signals for ``urns`` via aliases.

    Returns ``(query, variables)``. Aliases are ``d{i}`` and variables are ``$u{i}``,
    so callers can recover per-URN payloads via ``data["d{i}"]`` keyed by index.
    """

    if not urns:
        return "query DatasetFairSignalsBatch { __typename }", {}

    var_decls = ", ".join(f"$u{i}: String!" for i in range(len(urns)))
    aliases = " ".join(
        f"d{i}: dataset(urn: $u{i}) {{ {_DATASET_FAIR_SIGNALS_SELECTION} }}"
        for i in range(len(urns))
    )
    query = f"query DatasetFairSignalsBatch({var_decls}) {{ {aliases} }}"
    variables = {f"u{i}": urn for i, urn in enumerate(urns)}
    return query, variables


def parse_batch_fair_signals(
    root: Mapping[str, Any],
    urns: list[str],
) -> dict[str, DatasetFairSignals]:
    """Parse a batched GraphQL root into ``{urn: DatasetFairSignals}``.

    Missing aliases (``data["d{i}"]`` absent or ``null``) yield ``had_dataset=False``,
    matching the per-URN ``ENTITY_NOT_FOUND`` semantics in ``resolve_datahub_urn_flags``.
    """

    result: dict[str, DatasetFairSignals] = {}
    data = root.get("data") if isinstance(root, Mapping) else None
    if not isinstance(data, dict):
        for urn in urns:
            result[urn] = _EMPTY_DATASET_FAIR_SIGNALS
        return result
    for i, urn in enumerate(urns):
        result[urn] = _parse_dataset_node(data.get(f"d{i}"))
    return result
