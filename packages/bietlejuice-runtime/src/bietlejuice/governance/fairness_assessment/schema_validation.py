"""
Documented column model vs physical schema: bidirectional name alignment (I1-01)
and per-column description substance (F2-02) given governance text and a lowercased
field-name set.

Thin ``RequirementResult`` wrappers for row fields live in
``checks/findable/f2_02_substantive_column_descriptions`` and
``checks/interoperable/i1_01_documented_physical_fields``.

**Not** JSON Schema or Avro typing; alignment is to Spark/metastore field *names* and description text.
"""

from __future__ import annotations

import json
from typing import Any, Mapping, Optional

from bietlejuice.governance.fairness_assessment.constants import (
    DOCUMENTED_NOT_IN_PHYSICAL_REASON,
    PARTITION_COLUMN_NAMES_LOWERCASE,
    SCHEMA_NOT_IN_COLUMNS_METASTORE_REASON,
)
from bietlejuice.governance.fairness_assessment.description_quality import (
    assess_column_description_quality,
)
from bietlejuice.governance.fairness_assessment.models import RequirementResult

_DETAIL_LIST_CAP = 200


def _i1_01_schema_detail_json(
    undocumented_columns: list[str],
    documented_not_in_physical: list[str],
) -> str:
    """JSON for ``i1_01_undocumented_json`` / checks_result I1-01 detail (v12+)."""
    return json.dumps(
        {
            "undocumented_columns": undocumented_columns,
            "documented_not_in_physical": documented_not_in_physical,
        }
    )


def _f2_02_insufficient_detail_json(
    insufficient_columns: list[dict[str, str]],
) -> str:
    """JSON for ``f2_02_insufficient_json`` / checks_result F2-02 detail."""
    return json.dumps(
        {
            "insufficient_column_names": [
                row["column_name"] for row in insufficient_columns
            ],
            "insufficient_columns": insufficient_columns,
        }
    )


def _build_i1_01_reason(
    undocumented_columns: list[str],
    documented_not_in_physical: list[str],
) -> Optional[str]:
    parts: list[str] = []
    if undocumented_columns:
        parts.append("undocumented_columns")
    if documented_not_in_physical:
        parts.append(DOCUMENTED_NOT_IN_PHYSICAL_REASON)
    return ",".join(parts) if parts else None


def compute_f2_02_and_i1_01_for_fqn(
    database_name: str,
    table_name: str,
    column_name_to_desc: Mapping[str, Optional[str]],
    *,
    spark_table_exists: Optional[bool],
    physical_field_names_lower: frozenset[str],
) -> tuple[RequirementResult, RequirementResult, str, str, bool]:
    """Return (F2-02, I1-01, f2_02_insufficient_json, i1_01_schema_json, cols_substantive).

    ``spark_table_exists``: ``True`` if the FQN is present in the ``columns_metastore`` snapshot;
    ``False`` if absent; ``None`` if the snapshot could not be loaded (I1-01 → ``i1_01_not_assessed``).
    """

    has_physical = spark_table_exists is True and len(physical_field_names_lower) > 0
    col_map: dict[str, str] = {}
    for c, d in column_name_to_desc.items():
        ckey = (c or "").strip()
        if not ckey:
            continue
        col_map[ckey] = d if d is None else str(d)

    f2_ok = True
    f2_reason: Optional[str] = None
    f2_json = "{}"
    insufficient: list[dict[str, str]] = []
    assessed_non_partition = False

    if has_physical and not col_map:
        f2_ok, f2_reason = False, "no_column_docs_in_lake"
        columns_description_is_substantive = False
    else:
        for cname, desc in col_map.items():
            if cname.lower() in PARTITION_COLUMN_NAMES_LOWERCASE:
                continue
            assessed_non_partition = True
            q = assess_column_description_quality(
                database_name, table_name, cname, desc
            )
            if not q.is_substantive:
                insufficient.append(
                    {
                        "column_name": cname,
                        "reason_code": q.reason_code or "not_substantive",
                    }
                )
        if insufficient:
            columns_description_is_substantive = False
            f2_ok, f2_reason = False, "column_description_not_substantive"
            f2_json = _f2_02_insufficient_detail_json(insufficient)
        elif assessed_non_partition:
            columns_description_is_substantive = True
        elif col_map:
            columns_description_is_substantive = True
        else:
            columns_description_is_substantive = False

    doc_lower = {c.lower() for c in col_map if c}
    undocumented_columns: list[str] = []
    documented_not_in_physical: list[str] = []
    if has_physical:
        undocumented_columns = sorted(
            phy for phy in physical_field_names_lower if phy not in doc_lower
        )[:_DETAIL_LIST_CAP]
        documented_not_in_physical = sorted(
            c for c in doc_lower if c not in physical_field_names_lower
        )[:_DETAIL_LIST_CAP]

    i1_ok = (not undocumented_columns) and (not documented_not_in_physical)
    i1_reason = _build_i1_01_reason(undocumented_columns, documented_not_in_physical)
    i1_json = _i1_01_schema_detail_json(
        undocumented_columns, documented_not_in_physical
    )

    f2r = RequirementResult(
        "F2-02",
        f2_ok,
        reason=None if f2_ok else f2_reason,
    )
    if spark_table_exists is None:
        i1r = RequirementResult("I1-01", False, "i1_01_not_assessed")
        return (f2r, i1r, f2_json, "{}", columns_description_is_substantive)
    if spark_table_exists is False:
        i1r = RequirementResult(
            "I1-01",
            False,
            SCHEMA_NOT_IN_COLUMNS_METASTORE_REASON,
        )
        return (f2r, i1r, f2_json, "{}", columns_description_is_substantive)

    i1r = RequirementResult(
        "I1-01",
        i1_ok,
        reason=i1_reason,
    )
    return (
        f2r,
        i1r,
        f2_json,
        i1_json,
        columns_description_is_substantive,
    )
