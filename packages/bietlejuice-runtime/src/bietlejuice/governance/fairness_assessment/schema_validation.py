"""
Documented column model vs physical schema: name coverage (I1-01) and per-column
description substance (F2-02) given governance text and a lowercased field-name set.

Thin ``RequirementResult`` wrappers for row fields live in
``checks/findable/f2_02_substantive_column_descriptions`` and
``checks/interoperable/i1_01_documented_physical_fields``.

**Not** JSON Schema or Avro typing; alignment is to Spark/metastore field *names* and description text.
"""

from __future__ import annotations

import json
from typing import Any, Mapping, Optional

from bietlejuice.governance.fairness_assessment.constants import (
    PARTITION_COLUMN_NAMES_LOWERCASE,
    SCHEMA_NOT_IN_COLUMNS_METASTORE_REASON,
)
from bietlejuice.governance.fairness_assessment.description_quality import (
    assess_column_description_quality,
)
from bietlejuice.governance.fairness_assessment.models import RequirementResult


def _i1_01_undocumented_detail_json(
    all_missing_lower: list[str],
) -> str:
    """JSON for ``i1_01_undocumented_json``: business vs partition-only + optional warnings (I1-01)."""
    s = set(all_missing_lower)
    business = sorted(s - PARTITION_COLUMN_NAMES_LOWERCASE)[:200]
    partition_only = sorted(s & PARTITION_COLUMN_NAMES_LOWERCASE)
    i1_ok = not business
    d: dict[str, Any] = {
        "undocumented_business_names": business,
        "undocumented_partition_names": partition_only,
    }
    if i1_ok and partition_only:
        d["warnings"] = [
            "undocumented_partition_columns: " + ", ".join(partition_only),
        ]
    return json.dumps(d)


def compute_f2_02_and_i1_01_for_fqn(
    database_name: str,
    table_name: str,
    column_name_to_desc: Mapping[str, Optional[str]],
    *,
    spark_table_exists: Optional[bool],
    physical_field_names_lower: frozenset[str],
) -> tuple[RequirementResult, RequirementResult, str, bool]:
    """Return (F2-02, I1-01, JSON for ``i1_01_undocumented_json``, columns_description_is_substantive).

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

    columns_description_is_substantive = bool(col_map)
    f2_ok = True
    f2_reason: Optional[str] = None
    if has_physical and not col_map:
        f2_ok, f2_reason = False, "no_column_docs_in_lake"
    else:
        if col_map:
            columns_description_is_substantive = True
        for cname, desc in col_map.items():
            q = assess_column_description_quality(
                database_name, table_name, cname, desc
            )
            if not q.is_substantive:
                columns_description_is_substantive = False
                f2_ok, f2_reason = False, "column_description_not_substantive"
                break

    missing: list[str] = []
    if has_physical:
        doc_lower = {c.lower() for c in col_map if c}
        for phy in physical_field_names_lower:
            if phy not in doc_lower:
                missing.append(phy)

    s_missing = set(missing)
    business = s_missing - PARTITION_COLUMN_NAMES_LOWERCASE
    i1_ok = not business
    i1_reason: Optional[str] = None
    if not i1_ok:
        i1_reason = "undocumented_columns"

    miss_sorted = sorted(missing)[:200]
    f2r = RequirementResult(
        "F2-02",
        f2_ok,
        reason=None if f2_ok else f2_reason,
    )
    if spark_table_exists is None:
        i1r = RequirementResult("I1-01", False, "i1_01_not_assessed")
        return (f2r, i1r, "{}", columns_description_is_substantive)
    if spark_table_exists is False:
        i1r = RequirementResult(
            "I1-01",
            False,
            SCHEMA_NOT_IN_COLUMNS_METASTORE_REASON,
        )
        return (f2r, i1r, "{}", columns_description_is_substantive)

    i1r = RequirementResult(
        "I1-01",
        i1_ok,
        reason=None if i1_ok else i1_reason,
    )
    return (
        f2r,
        i1r,
        _i1_01_undocumented_detail_json(miss_sorted),
        columns_description_is_substantive,
    )
