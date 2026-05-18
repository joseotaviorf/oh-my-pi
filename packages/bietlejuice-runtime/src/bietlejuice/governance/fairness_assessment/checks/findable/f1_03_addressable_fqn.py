from __future__ import annotations

from typing import Optional

from bietlejuice.governance.fairness_assessment.checks.patterns import IDENTIFIER_RE
from bietlejuice.governance.fairness_assessment.constants import (
    COLUMNS_METASTORE_SNAPSHOT_UNAVAILABLE_REASON,
    FQN_NOT_IN_COLUMNS_METASTORE_REASON,
)
from bietlejuice.governance.fairness_assessment.models import RequirementResult


def check_f1_03_addressable_fqn(
    database_name: Optional[str],
    table_name: Optional[str],
    *,
    spark_catalog_hit: Optional[bool] = None,
    spark_catalog_probe_status: Optional[str] = None,
) -> RequirementResult:
    """F1-03: addressable FQN — valid Hive/Spark identifier shape and table exists in catalog.

    ``spark_catalog_hit`` reflects presence in ``information_schema.columns`` for this FQN
    (joined to assessed documentation FQNs). ``True`` when columns exist for the FQN;
    ``False`` when absent; ``None`` when catalog resolution failed (fail closed).

    ``spark_catalog_probe_status`` disambiguates: ``in_snapshot``, ``missing_in_snapshot``,
    ``snapshot_unavailable`` (legacy labels retained for downstream consumers).
    """
    if database_name is None or table_name is None:
        return RequirementResult(
            requirement_id="F1-03",
            passed=False,
            reason="missing_fqn_components",
        )
    db = str(database_name).strip()
    tbl = str(table_name).strip()
    shape_ok = bool(IDENTIFIER_RE.match(db) and IDENTIFIER_RE.match(tbl))
    if not shape_ok:
        return RequirementResult(
            requirement_id="F1-03",
            passed=False,
            reason="invalid_identifier_format",
        )
    if spark_catalog_hit is None:
        return RequirementResult(
            requirement_id="F1-03",
            passed=False,
            reason=COLUMNS_METASTORE_SNAPSHOT_UNAVAILABLE_REASON,
        )
    if not spark_catalog_hit:
        ps = (spark_catalog_probe_status or "").strip()
        if ps == "snapshot_unavailable":
            return RequirementResult(
                requirement_id="F1-03",
                passed=False,
                reason=COLUMNS_METASTORE_SNAPSHOT_UNAVAILABLE_REASON,
            )
        return RequirementResult(
            requirement_id="F1-03",
            passed=False,
            reason=FQN_NOT_IN_COLUMNS_METASTORE_REASON,
        )
    return RequirementResult(requirement_id="F1-03", passed=True, reason=None)
