"""SCD Type 2 transforms for the Salesforce API_v2 clean layer.

API_v2 raw tables are daily incremental *snapshots* of created/changed records (one
row per ``id_record`` per ``partition_date``). This module turns each snapshot into an
SCD Type 2 history table with the generic versioning helper
:func:`bietlejuice.base.sst.core.utils.transforms.get_versioning_df`, ordering versions
by the record's own ``system_modstamp``.
"""

import pyspark.sql.functions as F
from pyspark.sql import DataFrame, SparkSession
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.sst.core.utils.common import (
    _table_exists,
    normalize_df_columns,
    safe_union_with_target_schema,
)
from bietlejuice.base.sst.core.utils.time import standardize_timestamps
from bietlejuice.base.sst.core.utils.transforms import (
    get_rows_to_update,
    get_versioning_df,
)

logger = QuintoAndarLogger("sst.domains.salesforce.clean.api_versioning")

# Raw-only lineage columns that should not be carried into the clean table. The raw
# ``ts_load`` (ingestion time) is replaced by a fresh clean ``ts_load`` in the pipeline.
RAW_ONLY_COLS = ["entity_type", "ts_load"]

# String timestamp columns (every API_v2 object has these) standardized before
# versioning so lexical ordering matches chronological ordering.
TS_COLS = ["created_date", "last_modified_date", "system_modstamp"]


def conform_api_clean(raw_df: DataFrame, context_col: str) -> DataFrame:
    """Normalize an API_v2 raw snapshot into clean-layer column conventions.

    Drops raw-only lineage columns, snake_cases every column (``IsDeleted`` ->
    ``is_deleted``, ``SystemModstamp`` -> ``system_modstamp`` …), standardizes the
    string timestamps, and defensively dedups to one row per ``context_col`` (raw is
    already unique per business key within a ``partition_date``).
    """
    df = raw_df.drop(*[c for c in RAW_ONLY_COLS if c in raw_df.columns])
    df = normalize_df_columns(df)
    df = standardize_timestamps(df, [c for c in TS_COLS if c in df.columns])
    return df.dropDuplicates([context_col])


def build_api_versioned_df(
    spark: SparkSession,
    conformed_df: DataFrame,
    target_table: str,
    context_col: str,
    event_ts_col: str,
) -> DataFrame:
    """Add SCD Type 2 versioning columns to a conformed daily snapshot.

    On the first run (target absent) every record becomes its own open version. On
    subsequent runs the currently-open version of each touched ``id_record`` is read
    back from the target (:func:`get_rows_to_update`), unioned with the new rows and
    re-versioned — so the prior version is closed (``_is_current=false`` with its
    ``_expired_timestamp`` set) and exactly one ``_is_current=true`` row remains per
    ``id_record``. Mirrors ``cases.py:238-272``.

    The returned frame carries ``get_versioning_df``'s columns: ``_effective_timestamp``,
    ``_expired_timestamp``, ``_is_current``, ``_created_at``, ``_last_updated_at``.
    """
    # Seed ``_created_at`` (consumed by get_versioning_df's first()-over-window) with
    # the record's Salesforce creation date.
    conformed_df = conformed_df.withColumn("_created_at", F.col("created_date"))

    if _table_exists(spark, target_table):
        target_cols = spark.read.table(target_table).columns
        rows_to_update = get_rows_to_update(
            spark, target_table, conformed_df, context_col
        )
        unioned = safe_union_with_target_schema(
            conformed_df, rows_to_update, target_cols
        )
        # Guard against a record re-pulled with an unchanged SystemModstamp: collapse
        # to one row per (id_record, system_modstamp) so versioning never produces a
        # duplicate effective timestamp (which would break the downstream MERGE).
        unioned = unioned.dropDuplicates([context_col, event_ts_col])
        logger.info(
            "m=build_api_versioned_df, msg=Incremental versioning against existing target"
        )
    else:
        unioned = conformed_df
        logger.info(
            "m=build_api_versioned_df, msg=Bootstrap versioning (target does not exist)"
        )

    # id_record is unique per partition_date, so system_modstamp alone orders versions.
    return get_versioning_df(unioned, context_col, event_ts_col)
