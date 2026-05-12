from __future__ import annotations

from typing import Optional

from bietlejuice.governance.fairness_assessment.models import RequirementResult


def check_f1_01_persistent_id(
    database_name: Optional[str],
    table_name: Optional[str],
) -> RequirementResult:
    """F1-01: both parts of the FQN must be present.

    In ``tables_documentation``, ``database_name`` is the metastore **schema** (Hive/Spark
    ``database``); ``table_name`` is the table. The persistent ID is ``<database_name>.<table_name>``
    """
    db_ok = database_name is not None and str(database_name).strip() != ""
    tbl_ok = table_name is not None and str(table_name).strip() != ""
    ok = db_ok and tbl_ok
    return RequirementResult(
        requirement_id="F1-01",
        passed=ok,
        reason=None if ok else "missing_database_name_or_table_name",
    )
