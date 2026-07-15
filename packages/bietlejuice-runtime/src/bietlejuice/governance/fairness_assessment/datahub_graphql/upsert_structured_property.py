"""Write path: upsert the FAIRness classification structured property onto DataHub datasets.

Read-side signals live in :mod:`compute_fqn_datahub_signals`; this module is the only place that
**mutates** DataHub. Matching is **FQN-based and platform-agnostic**: for each ``(database_name,
table_name)`` we search DataHub for ``DATASET`` entities and keep those whose fully-qualified name
ends with ``<database_name>.<table_name>``, then ``upsertStructuredProperties`` on every match
regardless of data platform (trino ``hive.db.table``, databricks ``db.table``, or any future one).

**Important:** DataHub's ``upsertStructuredProperties`` *replaces* **all** structured properties on the
asset. We therefore pre-fetch the dataset's existing SPs and merge the fairness label in (same pattern
as ``datahub_document_client`` / ``load_collections_context``) so sibling keys — data contract, how to
request access, etc. — are preserved.

Fail-soft by contract: :func:`push_classifications` never raises. A DataHub outage, an unknown
label, or a missing entity is logged and counted in the returned summary so the Airflow task can
succeed and surface the numbers instead of blocking the DAG on a metadata write.
"""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Any, Iterable, Mapping, NamedTuple, Optional

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.governance.fairness_assessment.constants import (
    DATAHUB_GRAPHQL_BATCH_TIMEOUT_SEC,
    DATAHUB_GRAPHQL_BATCH_WORKERS,
    DATAHUB_SP_FAIRNESS_CLASSIFICATION_URN,
)
from bietlejuice.governance.fairness_assessment.datahub_graphql.client import (
    datahub_graphql_post,
)
from bietlejuice.governance.fairness_assessment.tiering import (
    normalize_classification_to_sp_value,
)

LOGGER = QuintoAndarLogger(__name__)

# ``searchAcrossEntities`` is fuzzy: we ask for up to this many hits, then keep only exact FQN
# matches via ``fqn_matches``. 50 is plenty for the few platform entities that share one lake FQN
# (typically trino + databricks = 2). If a fuzzy query ever returned >50 hits and the true match
# sat beyond that page, it would be missed — raise this constant (or paginate) if that ever shows up.
DATASET_FQN_SEARCH_COUNT = 50

_DATASET_FQN_SEARCH_QUERY = (
    "query DatasetFqnSearch($query: String!, $count: Int!) { "
    "searchAcrossEntities(input: {types: [DATASET], query: $query, start: 0, count: $count}) { "
    "total searchResults { entity { urn } } } }"
)

# Prefetch before upsert — mutation replaces the entire structuredProperties aspect.
_FETCH_DATASET_STRUCTURED_PROPERTIES_QUERY = (
    "query FetchDatasetStructuredProperties($urn: String!) { "
    "dataset(urn: $urn) { structuredProperties { properties { "
    "structuredProperty { urn } "
    "values { ... on StringValue { stringValue } ... on NumberValue { numberValue } } "
    "} } } }"
)

_UPSERT_STRUCTURED_PROPERTIES_MUTATION = (
    "mutation UpsertStructuredProperties($input: UpsertStructuredPropertiesInput!) { "
    "upsertStructuredProperties(input: $input) { "
    "properties { structuredProperty { urn } } } }"
)


class ClassificationPushResult(NamedTuple):
    """Per-FQN outcome of the DataHub push (rolled up by :func:`push_classifications`)."""

    database_name: str
    table_name: str
    sp_value: Optional[str]
    matched_urns: tuple[str, ...]
    upserted_urns: tuple[str, ...]
    skipped_reason: Optional[str]


# -- query / mutation builders -----------------------------------------------------------------


def build_dataset_fqn_search_query(
    fqn_query: str, count: int = DATASET_FQN_SEARCH_COUNT
) -> tuple[str, dict[str, Any]]:
    """Build the ``searchAcrossEntities`` query for datasets matching ``fqn_query``."""

    return _DATASET_FQN_SEARCH_QUERY, {"query": fqn_query, "count": count}


def build_fetch_dataset_structured_properties_query(
    asset_urn: str,
) -> tuple[str, dict[str, str]]:
    """Build the prefetch query used before a merge-upsert of structured properties."""

    return _FETCH_DATASET_STRUCTURED_PROPERTIES_QUERY, {"urn": asset_urn}


def build_upsert_structured_property_mutation(
    asset_urn: str,
    sp_urn: str,
    value: str,
    *,
    existing_property_params: Optional[list[dict[str, Any]]] = None,
) -> tuple[str, dict[str, Any]]:
    """Build ``upsertStructuredProperties`` merging ``(sp_urn, value)`` with existing params.

    ``existing_property_params`` should already exclude ``sp_urn`` (see
    :func:`structured_property_rows_from_fetch`). Passing only the new property without siblings
    would wipe other SPs on the asset — DataHub replaces the whole aspect.
    """

    params: list[dict[str, Any]] = list(existing_property_params or [])
    params.append(
        {
            "structuredPropertyUrn": sp_urn,
            "values": [{"stringValue": value}],
        }
    )
    return _UPSERT_STRUCTURED_PROPERTIES_MUTATION, {
        "input": {
            "assetUrn": asset_urn,
            "structuredPropertyInputParams": params,
        }
    }


# -- URN / FQN parsing --------------------------------------------------------------------------


def dataset_name_from_urn(urn: str) -> Optional[str]:
    """Extract the ``<name>`` segment from ``urn:li:dataset:(<platformUrn>,<name>,<fabric>)``.

    The platform URN has no comma, so splitting the parenthesised body on ``,`` yields
    ``[platformUrn, name, fabric]``. Returns ``None`` for an unparseable URN.
    """

    if not isinstance(urn, str):
        return None
    start = urn.find("(")
    end = urn.rfind(")")
    if start == -1 or end == -1 or end <= start:
        return None
    parts = urn[start + 1 : end].split(",")
    if len(parts) < 3:
        return None
    # Defensive: a name containing commas is rejoined; fabric is always the last field.
    return ",".join(parts[1:-1]).strip()


def fqn_matches(
    dataset_name: Optional[str], database_name: str, table_name: str
) -> bool:
    """True iff ``dataset_name``'s last two dot-segments equal ``(database_name, table_name)``.

    Matches ``hive.<db>.<table>`` (trino) and ``<db>.<table>`` (databricks) alike, so the push is
    platform-agnostic while still rejecting fuzzy-search false positives on a different table.
    """

    if not dataset_name:
        return False
    segments = [s for s in dataset_name.split(".") if s]
    if len(segments) < 2:
        return False
    return segments[-2] == database_name and segments[-1] == table_name


def parse_search_result_urns(root: Mapping[str, Any]) -> list[str]:
    """Pull dataset URNs out of a ``searchAcrossEntities`` GraphQL root."""

    data = root.get("data") if isinstance(root, Mapping) else None
    if not isinstance(data, dict):
        return []
    search = data.get("searchAcrossEntities")
    if not isinstance(search, dict):
        return []
    urns: list[str] = []
    for result in search.get("searchResults") or []:
        if not isinstance(result, dict):
            continue
        entity = result.get("entity")
        if not isinstance(entity, dict):
            continue
        urn = entity.get("urn")
        if isinstance(urn, str) and urn.strip():
            urns.append(urn.strip())
    return urns


def structured_property_rows_from_fetch(
    root: Mapping[str, Any],
    *,
    skip_sp_urns: frozenset[str] = frozenset(),
) -> list[dict[str, Any]]:
    """Convert a ``dataset.structuredProperties`` GraphQL root into upsert input rows.

    Skips URNs in ``skip_sp_urns`` (the property we are about to overwrite) and drops values that
    are neither string nor number (cannot safely round-trip via GraphQL String/NumberValue inputs).
    """

    data = root.get("data") if isinstance(root, Mapping) else None
    if not isinstance(data, dict):
        return []
    dataset = data.get("dataset")
    if not isinstance(dataset, dict):
        return []
    sp_block = dataset.get("structuredProperties")
    if not isinstance(sp_block, dict):
        return []

    rows: list[dict[str, Any]] = []
    for prop in sp_block.get("properties") or []:
        if not isinstance(prop, dict):
            continue
        sp_def = prop.get("structuredProperty") or {}
        if not isinstance(sp_def, dict):
            continue
        sp_u = sp_def.get("urn") or ""
        if not sp_u or sp_u in skip_sp_urns:
            continue
        converted: list[dict[str, Any]] = []
        for val in prop.get("values") or []:
            if not isinstance(val, dict):
                continue
            if val.get("stringValue") is not None:
                converted.append({"stringValue": val["stringValue"]})
            elif val.get("numberValue") is not None:
                converted.append({"numberValue": val["numberValue"]})
        if converted:
            rows.append({"structuredPropertyUrn": sp_u, "values": converted})
    return rows


# -- network operations -------------------------------------------------------------------------


def find_matching_dataset_urns(
    graphql_url: str,
    token: Optional[str],
    database_name: str,
    table_name: str,
    *,
    timeout_sec: float = DATAHUB_GRAPHQL_BATCH_TIMEOUT_SEC,
) -> Optional[list[str]]:
    """Search DataHub for datasets matching the FQN; return exact-match URNs (any platform).

    Returns ``None`` when the search POST itself failed (HTTP/timeout/JSON) so the caller can
    distinguish an outage from an empty result (``[]`` = reachable but nothing matched).
    """

    query, variables = build_dataset_fqn_search_query(f"{database_name}.{table_name}")
    root, _outcome = datahub_graphql_post(
        graphql_url, token, query, variables, timeout_sec=timeout_sec
    )
    if not root:
        return None
    return [
        urn
        for urn in parse_search_result_urns(root)
        if fqn_matches(dataset_name_from_urn(urn), database_name, table_name)
    ]


def _fetch_existing_property_params(
    graphql_url: str,
    token: Optional[str],
    asset_urn: str,
    sp_urn: str,
    timeout_sec: float,
) -> list[dict[str, Any]]:
    """Prefetch sibling SPs for ``asset_urn``, excluding ``sp_urn``. Empty on fetch failure."""

    query, variables = build_fetch_dataset_structured_properties_query(asset_urn)
    root, _outcome = datahub_graphql_post(
        graphql_url, token, query, variables, timeout_sec=timeout_sec
    )
    if not root:
        LOGGER.warning(
            f"m=datahub_sp_prefetch_failed,urn={asset_urn},"
            "msg=proceeding with fairness SP only — sibling SPs may be wiped"
        )
        return []
    return structured_property_rows_from_fetch(root, skip_sp_urns=frozenset({sp_urn}))


def _upsert_one(
    graphql_url: str,
    token: Optional[str],
    asset_urn: str,
    sp_urn: str,
    value: str,
    timeout_sec: float,
) -> bool:
    """Prefetch+merge+upsert one asset; True iff the response carried a non-null result payload."""

    existing = _fetch_existing_property_params(
        graphql_url, token, asset_urn, sp_urn, timeout_sec
    )
    query, variables = build_upsert_structured_property_mutation(
        asset_urn, sp_urn, value, existing_property_params=existing
    )
    root, outcome = datahub_graphql_post(
        graphql_url, token, query, variables, timeout_sec=timeout_sec
    )
    if not root:
        LOGGER.warning(
            f"m=datahub_sp_upsert_no_root,urn={asset_urn},outcome={outcome},"
            f"has_token={bool(token)},sibling_count={len(existing)}"
        )
        return False
    errors = root.get("errors")
    if errors:
        # GraphQL often returns HTTP 200 with null data + errors (auth / allowedValues / schema).
        err0 = errors[0] if isinstance(errors, list) and errors else errors
        LOGGER.warning(
            f"m=datahub_sp_upsert_graphql_error,urn={asset_urn},"
            f"sibling_count={len(existing)},err={err0!r}"
        )
    data = root.get("data")
    if not isinstance(data, dict):
        LOGGER.warning(
            f"m=datahub_sp_upsert_bad_data,urn={asset_urn},outcome={outcome},"
            f"root_keys={list(root.keys())}"
        )
        return False
    payload = data.get("upsertStructuredProperties")
    if payload is None:
        LOGGER.warning(
            f"m=datahub_sp_upsert_null_payload,urn={asset_urn},"
            f"sibling_count={len(existing)},has_errors={bool(errors)}"
        )
        return False
    return True


def _process_fqn(
    graphql_url: str,
    token: Optional[str],
    sp_urn: str,
    database_name: str,
    table_name: str,
    classification: Optional[str],
    timeout_sec: float,
) -> ClassificationPushResult:
    """Normalize one row's label, resolve matching URNs, and upsert the SP on each. Never raises."""

    def _result(
        sp_value: Optional[str],
        matched: Iterable[str] = (),
        upserted: Iterable[str] = (),
        skipped_reason: Optional[str] = None,
    ) -> ClassificationPushResult:
        return ClassificationPushResult(
            database_name=database_name,
            table_name=table_name,
            sp_value=sp_value,
            matched_urns=tuple(matched),
            upserted_urns=tuple(upserted),
            skipped_reason=skipped_reason,
        )

    sp_value = normalize_classification_to_sp_value(classification)
    if sp_value is None:
        LOGGER.warning(
            f"m=datahub_sp_skip_unknown_classification,db={database_name},"
            f"table={table_name},classification={classification!r}"
        )
        return _result(None, skipped_reason="unknown_classification")

    try:
        matched = find_matching_dataset_urns(
            graphql_url,
            token,
            database_name,
            table_name,
            timeout_sec=timeout_sec,
        )
    except Exception as exc:  # fail-soft: one FQN must not abort the whole push
        LOGGER.warning(
            f"m=datahub_sp_search_error,db={database_name},table={table_name},err={exc}"
        )
        return _result(sp_value, skipped_reason="search_error")

    if matched is None:
        return _result(sp_value, skipped_reason="datahub_unreachable")
    if not matched:
        return _result(sp_value, skipped_reason="no_matching_dataset")

    upserted: list[str] = []
    for urn in matched:
        try:
            ok = _upsert_one(graphql_url, token, urn, sp_urn, sp_value, timeout_sec)
        except Exception as exc:  # fail-soft per URN
            LOGGER.warning(f"m=datahub_sp_upsert_error,urn={urn},err={exc}")
            ok = False
        if ok:
            upserted.append(urn)
    if not upserted:
        LOGGER.warning(
            f"m=datahub_sp_matched_but_upsert_failed,db={database_name},"
            f"table={table_name},matched={len(matched)},sp_value={sp_value!r}"
        )
        return _result(
            sp_value,
            matched=matched,
            skipped_reason="matched_but_upsert_failed",
        )
    return _result(sp_value, matched=matched, upserted=upserted)


def push_classifications(
    graphql_url: str,
    token: Optional[str],
    rows: Iterable[Any],
    *,
    sp_urn: str = DATAHUB_SP_FAIRNESS_CLASSIFICATION_URN,
    workers: Optional[int] = None,
    timeout_sec: float = DATAHUB_GRAPHQL_BATCH_TIMEOUT_SEC,
) -> dict[str, Any]:
    """Upsert the classification SP on every DataHub dataset matching each row's FQN.

    ``rows`` is an iterable of ``(database_name, table_name, classification)`` triples (Spark Rows
    or tuples). Returns a summary dict of counts; **never raises** (fail-soft). When ``graphql_url``
    is empty the push is skipped entirely (mirrors the read-side ``datahub_host_unconfigured``).
    """

    triples: list[tuple[str, str, Optional[str]]] = []
    for r in rows:
        db, tbl, classification = r[0], r[1], r[2]
        if db is None or tbl is None:
            continue
        db_s, tbl_s = str(db).strip(), str(tbl).strip()
        if not db_s or not tbl_s:
            continue
        triples.append((db_s, tbl_s, classification))

    summary: dict[str, Any] = {
        "total_fqns": len(triples),
        "upserted_entities": 0,
        "fqns_with_upsert": 0,
        "skipped_unknown_classification": 0,
        "skipped_no_matching_dataset": 0,
        "skipped_datahub_unreachable": 0,
        "skipped_search_error": 0,
        "matched_but_upsert_failed": 0,
    }

    if not graphql_url:
        LOGGER.warning(
            "m=datahub_sp_push_skipped,reason=datahub_host_unconfigured,"
            f"total_fqns={len(triples)}"
        )
        summary["skipped_reason"] = "datahub_host_unconfigured"
        return summary
    if not triples:
        LOGGER.info("m=datahub_sp_push_summary,total_fqns=0")
        return summary

    resolved_workers = workers or DATAHUB_GRAPHQL_BATCH_WORKERS
    effective_workers = max(1, min(resolved_workers, len(triples)))

    results: list[ClassificationPushResult] = []
    with ThreadPoolExecutor(max_workers=effective_workers) as pool:
        futures = [
            pool.submit(
                _process_fqn,
                graphql_url,
                token,
                sp_urn,
                db,
                tbl,
                classification,
                timeout_sec,
            )
            for db, tbl, classification in triples
        ]
        for fut in as_completed(futures):
            results.append(fut.result())

    _reason_to_key = {
        "unknown_classification": "skipped_unknown_classification",
        "no_matching_dataset": "skipped_no_matching_dataset",
        "datahub_unreachable": "skipped_datahub_unreachable",
        "search_error": "skipped_search_error",
        "matched_but_upsert_failed": "matched_but_upsert_failed",
    }
    for res in results:
        if res.upserted_urns:
            summary["fqns_with_upsert"] += 1
            summary["upserted_entities"] += len(res.upserted_urns)
        if res.skipped_reason in _reason_to_key:
            summary[_reason_to_key[res.skipped_reason]] += 1

    LOGGER.info(
        "m=datahub_sp_push_summary,"
        f"total_fqns={summary['total_fqns']},"
        f"fqns_with_upsert={summary['fqns_with_upsert']},"
        f"upserted_entities={summary['upserted_entities']},"
        f"skipped_unknown_classification={summary['skipped_unknown_classification']},"
        f"skipped_no_matching_dataset={summary['skipped_no_matching_dataset']},"
        f"skipped_datahub_unreachable={summary['skipped_datahub_unreachable']},"
        f"skipped_search_error={summary['skipped_search_error']},"
        f"matched_but_upsert_failed={summary['matched_but_upsert_failed']}"
    )
    return summary
