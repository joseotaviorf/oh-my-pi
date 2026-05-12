"""Read physical column names from the daily ``columns_metastore`` snapshot (clean layer)."""

from __future__ import annotations

from typing import Any, Optional, Set, Tuple

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.governance.fairness_assessment.constants import COLUMNS_METASTORE

LOGGER = QuintoAndarLogger(__name__)


def resolve_columns_metastore_snapshot(
    spark: Any,
    environment: str,
    td_df: Any,
) -> Tuple[Set[Tuple[str, str]], dict[Tuple[str, str], frozenset[str]], Optional[str]]:
    """Load latest partition of ``columns_metastore`` and aggregate physical column names per FQN.

    Joins to distinct (database_name, table_name) from ``td_df`` so only assessed FQNs are processed.

    Returns:
        exists_set: FQNs present in the snapshot for the latest partition (inner join with td).
        field_map: lowercased Spark field names per FQN (may be empty if column_name rows are null).
        snapshot_partition_iso: ``YYYY-MM-DD`` for the partition read, or ``None`` if the table is
        empty/unreadable (caller should treat all FQNs as snapshot unavailable).

    Replaces per-FQN ``spark.catalog.tableExists`` + ``spark.table`` probes for F1-03 / I1-01.
    """

    db, tbl = COLUMNS_METASTORE
    fqn = f"quintoandar_{environment}.{db}.{tbl}"
    try:
        cm = spark.table(fqn)
    except Exception as e:
        LOGGER.warning(
            "m=columns_metastore_read_failed,"
            f"table={fqn},exception_type={type(e).__name__},msg=falling back to empty snapshot"
        )
        return set(), {}, None

    from pyspark.sql import functions as F

    snap_expr = F.make_date(
        F.col("year").cast("int"),
        F.col("month").cast("int"),
        F.col("day").cast("int"),
    )
    max_row = cm.select(F.max(snap_expr).alias("snap")).first()
    if max_row is None or max_row[0] is None:
        LOGGER.warning(
            "m=columns_metastore_empty_partition,table=%s,msg=no dated rows", fqn
        )
        return set(), {}, None

    snap = max_row[0]
    cm_snap = cm.filter(snap_expr == F.lit(snap))

    distinct_td = td_df.select("database_name", "table_name").distinct()
    joined = cm_snap.join(
        distinct_td,
        on=["database_name", "table_name"],
        how="inner",
    )

    agg = joined.groupBy("database_name", "table_name").agg(
        F.collect_set(F.lower(F.trim(F.col("column_name")))).alias("cols")
    )
    rows = agg.collect()

    exists_set: Set[Tuple[str, str]] = set()
    field_map: dict[Tuple[str, str], frozenset[str]] = {}
    for r in rows:
        db_s = str(r["database_name"] or "").strip()
        tbl_s = str(r["table_name"] or "").strip()
        key = (db_s, tbl_s)
        exists_set.add(key)
        raw_cols = r["cols"]
        if raw_cols is None:
            field_map[key] = frozenset()
        else:
            field_map[key] = frozenset(c for c in raw_cols if c)

    partition_str = (
        snap.strftime("%Y-%m-%d") if hasattr(snap, "strftime") else str(snap)
    )
    LOGGER.info(
        "m=columns_metastore_snapshot_loaded,"
        f"partition={partition_str},fqn_count={len(exists_set)}"
    )
    return exists_set, field_map, partition_str
