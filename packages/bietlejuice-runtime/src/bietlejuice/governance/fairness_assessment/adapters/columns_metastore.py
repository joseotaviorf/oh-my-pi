"""Resolve physical column names for assessed FQNs from Unity Catalog ``information_schema``."""

from __future__ import annotations

from typing import Any, Optional, Set, Tuple

from quintoandar_logger import QuintoAndarLogger

LOGGER = QuintoAndarLogger(__name__)

INFORMATION_SCHEMA_COLUMNS_TABLE_NAME = "system.information_schema.columns"


def _exists_set_and_field_map_from_collect_rows(
    rows: list[Any],
) -> Tuple[Set[Tuple[str, str]], dict[Tuple[str, str], frozenset[str]]]:
    """Build ``exists_set`` and per-FQN lowercased physical column names from aggregate rows."""
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
            field_map[key] = frozenset(
                str(c).lower().strip()
                for c in raw_cols
                if c is not None and str(c).strip() != ""
            )
    return exists_set, field_map


def resolve_physical_columns_from_information_schema(
    spark: Any,
    td_df: Any,
) -> Tuple[Set[Tuple[str, str]], dict[Tuple[str, str], frozenset[str]], Optional[str]]:
    """Load column names from ``system.information_schema.columns`` for FQNs in ``td_df`` only.

    Inner-joins Information Schema to ``distinct(database_name, table_name)`` from ``td_df``
    (broadcast on the key side when possible) so work scales with assessed tables, not the full
    catalog. Used for F1-03 / I1-01 instead of the ``columns_metastore`` Delta snapshot.

    Returns:
        exists_set: FQNs that have at least one row in ``information_schema.columns`` after join.
        field_map: lowercased Spark field names per FQN (may be empty if column_name rows are null).
        catalog_resolution_tag: ``information_schema:{catalog}`` when the read succeeds,
            or ``None`` if the Information Schema could not be read (caller should treat all FQNs
            as catalog-unavailable).

    """
    from pyspark.sql import functions as F
    from pyspark.sql.functions import broadcast

    distinct_td = td_df.select("database_name", "table_name").distinct()

    try:
        catalog = str(spark.catalog.currentCatalog())
        catalog_sql = catalog.replace("'", "''")
        isc = (
            spark.table(INFORMATION_SCHEMA_COLUMNS_TABLE_NAME)
            .filter(f"table_catalog = '{catalog_sql}'")
            .select(
                F.col("table_schema").alias("database_name"),
                F.col("table_name"),
                F.col("column_name"),
            )
        )
        joined = isc.join(
            broadcast(distinct_td),
            on=["database_name", "table_name"],
            how="inner",
        )
    except Exception as e:
        LOGGER.warning(
            "m=information_schema_columns_read_failed,"
            f"exception_type={type(e).__name__},msg=falling back to empty catalog resolution"
        )
        return set(), {}, None

    agg = joined.groupBy("database_name", "table_name").agg(
        F.collect_set(F.col("column_name")).alias("cols")
    )
    rows = agg.collect()
    exists_set, field_map = _exists_set_and_field_map_from_collect_rows(rows)

    tag = f"information_schema:{catalog}"
    LOGGER.info(
        "m=information_schema_columns_loaded,"
        f"catalog={catalog},fqn_count={len(exists_set)}"
    )
    return exists_set, field_map, tag
