"""Resolve DataHub fair signals per dataset URN (GraphQL), then roll up to FQN (F4-01, I1-02, I3)."""

from __future__ import annotations

from typing import Any, Optional

from bietlejuice.governance.fairness_assessment.constants import (
    DATAHUB_CHECK_FAILED,
    DATAHUB_DATASET_FAIR_SIGNALS_QUERY,
    DATAHUB_ENTITY_NOT_FOUND,
    DATAHUB_FETCH_ERROR,
    DATAHUB_F4_REASON_HOST_UNCONFIGURED,
    DATAHUB_F4_REASON_NO_CANDIDATE_URNS,
    DATAHUB_HTTP_ERROR,
    DATAHUB_URN_DIAG_OK,
)
from bietlejuice.governance.fairness_assessment.datahub_graphql.client import (
    _parse_dataset_fair_signals,
    datahub_graphql_post,
)
from bietlejuice.governance.fairness_assessment.datahub_graphql.urn_builder import (
    list_platform_urns_for_fqn,
)


def resolve_datahub_urn_flags(
    graphql_url: str,
    token: Optional[str],
    distinct_fqn_rows: list[Any],
) -> tuple[
    dict[str, bool],
    dict[str, bool],
    dict[str, str],
    dict[str, bool],
    dict[str, int],
    dict[str, int],
]:
    """One GraphQL POST per unique URN.

    Returns (urn_hit, urn_contract, urn_diagnostic, urn_ownership_nonempty, urn_upstream_total,
    urn_downstream_total).

    **F4-01 / urn_hit:** ``dataset.exists`` from GraphQL.

    **I1-02 / urn_contract:** ``institutionalMemory`` labels containing ``urn:prod:datacontract:`` for
    Databricks URNs only.

    ``urn_diagnostic`` reuses the same failure tokens for F4-01 reason roll-up per FQN.
    """

    urns_ordered: list[str] = []
    seen: set[str] = set()
    for r in distinct_fqn_rows:
        db = r["database_name"]
        tbl = r["table_name"]
        if db is None or tbl is None:
            continue
        db_s, tbl_s = str(db).strip(), str(tbl).strip()
        if not db_s or not tbl_s:
            continue
        srv_db = bool(r["contract_server_databricks"])
        srv_tr = bool(r["contract_server_trino"])
        for _platform, urn in list_platform_urns_for_fqn(
            db_s,
            tbl_s,
            server_databricks=srv_db,
            server_trino=srv_tr,
        ):
            if urn not in seen:
                seen.add(urn)
                urns_ordered.append(urn)

    urn_hit: dict[str, bool] = {}
    urn_contract: dict[str, bool] = {}
    urn_diagnostic: dict[str, str] = {}
    urn_ownership: dict[str, bool] = {}
    urn_upstream_total: dict[str, int] = {}
    urn_downstream_total: dict[str, int] = {}

    for urn in urns_ordered:
        root, outcome = datahub_graphql_post(
            graphql_url,
            token,
            DATAHUB_DATASET_FAIR_SIGNALS_QUERY,
            {"urn": urn},
        )
        if not root:
            urn_hit[urn] = False
            urn_contract[urn] = False
            urn_ownership[urn] = False
            urn_upstream_total[urn] = 0
            urn_downstream_total[urn] = 0
            urn_diagnostic[urn] = outcome
            continue
        indexed_ok, has_contract, ownership_nonempty, up_n, down_n, had_ds = (
            _parse_dataset_fair_signals(root)
        )
        if not had_ds:
            urn_hit[urn] = False
            urn_contract[urn] = False
            urn_ownership[urn] = False
            urn_upstream_total[urn] = 0
            urn_downstream_total[urn] = 0
            urn_diagnostic[urn] = DATAHUB_ENTITY_NOT_FOUND
            continue
        if not indexed_ok:
            urn_hit[urn] = False
            urn_contract[urn] = False
            urn_ownership[urn] = False
            urn_upstream_total[urn] = 0
            urn_downstream_total[urn] = 0
            urn_diagnostic[urn] = DATAHUB_ENTITY_NOT_FOUND
            continue

        urn_hit[urn] = True
        urn_ownership[urn] = ownership_nonempty
        urn_upstream_total[urn] = up_n
        urn_downstream_total[urn] = down_n
        is_databricks_urn = "dataPlatform:databricks" in urn
        urn_contract[urn] = bool(is_databricks_urn and has_contract)
        urn_diagnostic[urn] = DATAHUB_URN_DIAG_OK

    return (
        urn_hit,
        urn_contract,
        urn_diagnostic,
        urn_ownership,
        urn_upstream_total,
        urn_downstream_total,
    )


def compute_has_data_contract_by_fqn(
    distinct_fqn_rows: list[Any],
    urn_contract: dict[str, bool],
) -> dict[tuple[str, str], bool]:
    """I1-02: assigned data contract from Databricks entity only (``urn:prod:datacontract:`` in payload)."""

    result: dict[tuple[str, str], bool] = {}
    for r in distinct_fqn_rows:
        db = r["database_name"]
        tbl = r["table_name"]
        if db is None or tbl is None:
            key = (str(db or "").strip(), str(tbl or "").strip())
            result[key] = False
            continue
        db_s, tbl_s = str(db).strip(), str(tbl).strip()
        key = (db_s, tbl_s)
        if not db_s or not tbl_s:
            result[key] = False
            continue
        srv_db = bool(r["contract_server_databricks"])
        srv_tr = bool(r["contract_server_trino"])
        if not srv_db:
            result[key] = False
            continue
        databricks_urn = None
        for platform, urn in list_platform_urns_for_fqn(
            db_s,
            tbl_s,
            server_databricks=srv_db,
            server_trino=srv_tr,
        ):
            if platform == "databricks":
                databricks_urn = urn
                break
        if not databricks_urn:
            result[key] = False
            continue
        result[key] = bool(urn_contract.get(databricks_urn, False))
    return result


def compute_i3_ownership_pass_by_fqn(
    distinct_fqn_rows: list[Any],
    urn_ownership: dict[str, bool],
) -> dict[tuple[str, str], bool]:
    """I3-01: pass if **any** candidate platform URN has non-empty ownership."""

    result: dict[tuple[str, str], bool] = {}
    for r in distinct_fqn_rows:
        db = r["database_name"]
        tbl = r["table_name"]
        if db is None or tbl is None:
            key = (str(db or "").strip(), str(tbl or "").strip())
            result[key] = False
            continue
        db_s, tbl_s = str(db).strip(), str(tbl).strip()
        key = (db_s, tbl_s)
        if not db_s or not tbl_s:
            result[key] = False
            continue
        srv_db = bool(r["contract_server_databricks"])
        srv_tr = bool(r["contract_server_trino"])
        needed: list[str] = []
        for _platform, urn in list_platform_urns_for_fqn(
            db_s,
            tbl_s,
            server_databricks=srv_db,
            server_trino=srv_tr,
        ):
            needed.append(urn)
        if not needed:
            result[key] = False
            continue
        result[key] = any(bool(urn_ownership.get(u, False)) for u in needed)
    return result


def compute_i3_lineage_pass_and_totals_by_fqn(
    distinct_fqn_rows: list[Any],
    urn_upstream_total: dict[str, int],
    urn_downstream_total: dict[str, int],
) -> tuple[
    dict[tuple[str, str], bool], dict[tuple[str, str], int], dict[tuple[str, str], int]
]:
    """I3-02: pass if any URN has upstream>0 or downstream>0; totals = max per direction across URNs."""

    pass_m: dict[tuple[str, str], bool] = {}
    up_m: dict[tuple[str, str], int] = {}
    down_m: dict[tuple[str, str], int] = {}
    for r in distinct_fqn_rows:
        db = r["database_name"]
        tbl = r["table_name"]
        if db is None or tbl is None:
            key = (str(db or "").strip(), str(tbl or "").strip())
            pass_m[key] = False
            up_m[key] = 0
            down_m[key] = 0
            continue
        db_s, tbl_s = str(db).strip(), str(tbl).strip()
        key = (db_s, tbl_s)
        if not db_s or not tbl_s:
            pass_m[key] = False
            up_m[key] = 0
            down_m[key] = 0
            continue
        srv_db = bool(r["contract_server_databricks"])
        srv_tr = bool(r["contract_server_trino"])
        needed: list[str] = []
        for _platform, urn in list_platform_urns_for_fqn(
            db_s,
            tbl_s,
            server_databricks=srv_db,
            server_trino=srv_tr,
        ):
            needed.append(urn)
        if not needed:
            pass_m[key] = False
            up_m[key] = 0
            down_m[key] = 0
            continue
        ups = [int(urn_upstream_total.get(u, 0) or 0) for u in needed]
        downs = [int(urn_downstream_total.get(u, 0) or 0) for u in needed]
        max_up = max(ups) if ups else 0
        max_down = max(downs) if downs else 0
        up_m[key] = max_up
        down_m[key] = max_down
        pass_m[key] = max_up > 0 or max_down > 0
    return pass_m, up_m, down_m


def _f4_failure_reason_for_fqn(
    needed_urns: list[str],
    urn_hit: dict[str, bool],
    urn_diagnostic: dict[str, str],
) -> str:
    """Single F4-01 failure ``reason`` when no candidate URN hit (priority: HTTP → fetch → entity)."""

    if not needed_urns:
        return DATAHUB_F4_REASON_NO_CANDIDATE_URNS
    if any(urn_hit.get(u, False) for u in needed_urns):
        return ""

    diags = [urn_diagnostic.get(u, "") for u in needed_urns]
    if any(d == DATAHUB_HTTP_ERROR for d in diags):
        return DATAHUB_HTTP_ERROR
    if any(d == DATAHUB_FETCH_ERROR for d in diags):
        return DATAHUB_FETCH_ERROR
    if diags and all(d == DATAHUB_ENTITY_NOT_FOUND for d in diags):
        return DATAHUB_ENTITY_NOT_FOUND
    return DATAHUB_CHECK_FAILED


def compute_f4_pass_and_reason_by_fqn(
    distinct_fqn_rows: list[Any],
    urn_hit: dict[str, bool],
    urn_diagnostic: dict[str, str],
    *,
    datahub_host_configured: bool = True,
) -> tuple[dict[tuple[str, str], bool], dict[tuple[str, str], Optional[str]]]:
    """F4-01 pass map plus per-FQN failure reason (None when pass)."""

    pass_m: dict[tuple[str, str], bool] = {}
    reason_m: dict[tuple[str, str], Optional[str]] = {}
    for r in distinct_fqn_rows:
        db = r["database_name"]
        tbl = r["table_name"]
        if db is None or tbl is None:
            key = (str(db or "").strip(), str(tbl or "").strip())
            pass_m[key] = False
            reason_m[key] = (
                DATAHUB_F4_REASON_HOST_UNCONFIGURED
                if not datahub_host_configured
                else DATAHUB_F4_REASON_NO_CANDIDATE_URNS
            )
            continue
        db_s, tbl_s = str(db).strip(), str(tbl).strip()
        key = (db_s, tbl_s)
        if not db_s or not tbl_s:
            pass_m[key] = False
            reason_m[key] = (
                DATAHUB_F4_REASON_HOST_UNCONFIGURED
                if not datahub_host_configured
                else DATAHUB_F4_REASON_NO_CANDIDATE_URNS
            )
            continue
        if not datahub_host_configured:
            pass_m[key] = False
            reason_m[key] = DATAHUB_F4_REASON_HOST_UNCONFIGURED
            continue
        srv_db = bool(r["contract_server_databricks"])
        srv_tr = bool(r["contract_server_trino"])
        needed: list[str] = []
        for _platform, urn in list_platform_urns_for_fqn(
            db_s,
            tbl_s,
            server_databricks=srv_db,
            server_trino=srv_tr,
        ):
            needed.append(urn)
        if not needed:
            pass_m[key] = False
            reason_m[key] = DATAHUB_F4_REASON_NO_CANDIDATE_URNS
            continue
        ok = any(urn_hit.get(u, False) for u in needed)
        pass_m[key] = ok
        reason_m[key] = (
            None if ok else _f4_failure_reason_for_fqn(needed, urn_hit, urn_diagnostic)
        )
    return pass_m, reason_m
