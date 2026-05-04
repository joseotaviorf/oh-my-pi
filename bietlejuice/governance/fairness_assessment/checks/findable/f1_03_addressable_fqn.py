from __future__ import annotations

from typing import Optional

from bietlejuice.governance.fairness_assessment.checks.patterns import IDENTIFIER_RE
from bietlejuice.governance.fairness_assessment.models import RequirementResult


def check_f1_03_addressable_fqn(
    database_name: Optional[str],
    table_name: Optional[str],
    *,
    spark_catalog_hit: Optional[bool] = None,
    spark_catalog_probe_status: Optional[str] = None,
) -> RequirementResult:
    """F1-03: addressable FQN — valid Hive/Spark identifier shape and table exists in Spark catalog.

    ``spark_catalog_hit`` is mandatory: ``True`` only when ``spark.catalog.tableExists(f"{schema}.{table}")``
    succeeded for this FQN (two-part name; default catalog / Unity Catalog as configured). ``False`` means
    the table was not found; ``None`` means the probe was not provided — the requirement fails closed.

    ``spark_catalog_probe_status`` (optional) disambiguates ``False``: values ``exists`` / ``missing`` from
    a clean probe, or ``exception:…`` when ``tableExists`` raised — surfaced as ``spark_catalog_table_exists_exception``.

    Successful ``SELECT`` / full queryability is out of scope; catalog existence is the required signal.
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
            reason="spark_catalog_existence_not_assessed",
        )
    if not spark_catalog_hit:
        ps = (spark_catalog_probe_status or "").strip()
        if ps.startswith("exception"):
            fail_reason = "spark_catalog_table_exists_exception"
        else:
            fail_reason = "table_not_found_in_spark_catalog"
        return RequirementResult(
            requirement_id="F1-03",
            passed=False,
            reason=fail_reason,
        )
    return RequirementResult(requirement_id="F1-03", passed=True, reason=None)
