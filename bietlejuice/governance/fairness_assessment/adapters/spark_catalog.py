"""Spark catalog / table schema probes (only place that calls ``spark.catalog`` / ``spark.table``)."""

from __future__ import annotations

from typing import Any, Mapping

from quintoandar_logger import QuintoAndarLogger

LOGGER = QuintoAndarLogger(__name__)


def resolve_spark_table_exists_map(
    spark: Any,
    td_df: Any,
) -> tuple[dict[tuple[str, str], bool], dict[tuple[str, str], str]]:
    """Resolve ``spark.catalog.tableExists`` once per distinct FQN on the driver (not per row).

    Returns (exists_map, probe_status_map). ``probe_status_map`` values: ``exists``, ``missing``, or
    ``exception:<ExceptionTypeName>`` when the catalog probe raised.
    """

    distinct_rows = td_df.select("database_name", "table_name").distinct().collect()
    exists_out: dict[tuple[str, str], bool] = {}
    status_out: dict[tuple[str, str], str] = {}
    for r in distinct_rows:
        db, tbl = r["database_name"], r["table_name"]
        if db is None or tbl is None:
            key = (str(db or "").strip(), str(tbl or "").strip())
            exists_out[key] = False
            status_out[key] = "missing"
            continue
        db_s, tbl_s = str(db).strip(), str(tbl).strip()
        key = (db_s, tbl_s)
        if not db_s or not tbl_s:
            exists_out[key] = False
            status_out[key] = "missing"
            continue
        fqn = f"{db_s}.{tbl_s}"
        try:
            ex = bool(spark.catalog.tableExists(fqn))
            exists_out[key] = ex
            status_out[key] = "exists" if ex else "missing"
        except Exception as e:
            exists_out[key] = False
            et = type(e).__name__
            status_out[key] = f"exception:{et}"[:120]
    return exists_out, status_out


def resolve_spark_physical_field_names_lower(
    spark: Any,
    exists_map: Mapping[tuple[str, str], bool],
) -> dict[tuple[str, str], frozenset[str]]:
    """I1-01: lowercased field names for each FQN with ``tableExists`` True (empty on False / exception)."""

    out: dict[tuple[str, str], frozenset[str]] = {}
    for key, ex in exists_map.items():
        if not ex:
            out[key] = frozenset()
            continue
        db_s, tbl_s = key
        fqn = f"{db_s}.{tbl_s}"
        try:
            st = spark.table(fqn)
            out[key] = frozenset(f.name.lower() for f in st.schema.fields)
        except Exception as e:
            LOGGER.warning(
                "m=resolve_spark_physical_field_names_lower_failed,"
                f"database_name={db_s},table_name={tbl_s},"
                f"exception_type={type(e).__name__}"
            )
            out[key] = frozenset()
    return out
