"""MVP check evaluation for a single input row (driver or partition)."""

from __future__ import annotations

from typing import Any, Mapping, Optional

from bietlejuice.governance.fairness_assessment.checks.accessible import (
    check_a1_2_03_interim_access_policy_via_contract,
)
from bietlejuice.governance.fairness_assessment.checks.findable import (
    check_f1_01_persistent_id,
    check_f1_02_fqn_unique,
    check_f1_03_addressable_fqn,
    check_f2_01_basic_rich_metadata,
    check_f2_02_substantive_column_descriptions,
    check_f4_01_indexed_in_datahub,
)
from bietlejuice.governance.fairness_assessment.checks.interoperable import (
    check_i1_01_documented_physical_fields,
    check_i1_02_data_contract_present,
    check_i3_01_ownership_in_catalog,
    check_i3_02_lineage_in_catalog,
)
from bietlejuice.governance.fairness_assessment.constants import (
    DATAHUB_FETCH_ERROR,
    DATAHUB_HTTP_ERROR,
    DATAHUB_UNREACHABLE_REASON,
)
from bietlejuice.governance.fairness_assessment.models import RequirementResult

_DATAHUB_DEPENDENT_REQUIREMENT_IDS: tuple[str, ...] = (
    "I1-02",
    "I3-01",
    "I3-02",
    "A1.2-03",
)
_DATAHUB_UNREACHABLE_REASONS: frozenset[str] = frozenset(
    {DATAHUB_HTTP_ERROR, DATAHUB_FETCH_ERROR}
)


def evaluate_mvp_checks_from_row(
    row: Mapping[str, Any],
) -> dict[str, RequirementResult]:
    db = row.get("database_name")
    tbl = row.get("table_name")
    owner_raw = row.get("owner")
    owner_norm = row.get("owner_email_normalized")
    if owner_norm is None and owner_raw is not None:
        owner_norm = str(owner_raw).strip().lower()
    elif isinstance(owner_norm, str):
        owner_norm = owner_norm.strip().lower()

    is_active = bool(row.get("is_active_employee"))
    fqn_cnt = int(row.get("fqn_occurrence_count") or 0)

    out: dict[str, RequirementResult] = {}
    if "spark_table_exists" not in row:
        spark_hit: Optional[bool] = None
    else:
        _probe = row["spark_table_exists"]
        # Preserve None: bool(None) is False and would look like "table not found".
        spark_hit = None if _probe is None else bool(_probe)

    out["F1-01"] = check_f1_01_persistent_id(db, tbl)
    out["F1-02"] = check_f1_02_fqn_unique(fqn_cnt)
    probe_status = row.get("spark_catalog_probe_status")
    if isinstance(probe_status, str):
        probe_status = probe_status.strip() or None
    else:
        probe_status = None

    out["F1-03"] = check_f1_03_addressable_fqn(
        db,
        tbl,
        spark_catalog_hit=spark_hit,
        spark_catalog_probe_status=probe_status,
    )
    out["F2-01"] = check_f2_01_basic_rich_metadata(
        owner_norm,
        is_active,
        row.get("domain"),
        row.get("table_description"),
    )
    f4_ok = bool(row.get("f4_01_pass"))
    f4_reason = row.get("f4_01_failure_reason")
    if isinstance(f4_reason, str):
        f4_reason = f4_reason.strip() or None
    elif f4_reason is not None:
        f4_reason = str(f4_reason).strip() or None
    out["F4-01"] = check_f4_01_indexed_in_datahub(f4_ok, failure_reason=f4_reason)
    i1_ok = bool(row.get("has_data_contract"))
    out["I1-02"] = check_i1_02_data_contract_present(i1_ok)
    out["A1.2-03"] = check_a1_2_03_interim_access_policy_via_contract(i1_ok)
    out["F2-02"] = check_f2_02_substantive_column_descriptions(
        row.get("f2_02_pass"),
        row.get("f2_02_failure_reason"),
    )
    out["I1-01"] = check_i1_01_documented_physical_fields(
        row.get("i1_01_pass"),
        row.get("i1_01_failure_reason"),
    )
    if row.get("i3_01_pass") is not None:
        out["I3-01"] = check_i3_01_ownership_in_catalog(bool(row.get("i3_01_pass")))
    if row.get("i3_02_pass") is not None:
        out["I3-02"] = check_i3_02_lineage_in_catalog(bool(row.get("i3_02_pass")))

    # When DataHub itself is unreachable for the FQN, F4-01 already exposes the network-level reason
    # (HTTP_ERROR / FETCH_ERROR). Other DataHub-sourced checks only see empty maps and would fall back
    # to content-style reasons (e.g. ``ownership_empty_in_datahub``), misleading consumers into treating
    # an outage as missing metadata. Override their reason with a single ``datahub_unreachable`` token.
    if f4_reason in _DATAHUB_UNREACHABLE_REASONS:
        for rid in _DATAHUB_DEPENDENT_REQUIREMENT_IDS:
            current = out.get(rid)
            if current is not None and not current.passed:
                out[rid] = RequirementResult(
                    requirement_id=rid,
                    passed=False,
                    reason=DATAHUB_UNREACHABLE_REASON,
                )
    return out
