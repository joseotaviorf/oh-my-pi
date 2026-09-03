import pyspark.sql.functions as F
from pyspark.sql import Window
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.sst.core.utils.common import _table_exists, safe_column_union
from bietlejuice.base.sst.core.utils.transforms import nullify_fields_on_delete
from bietlejuice.base.sst.domains.salesforce.clean.check import (
    check_for_create_partition,
)

logger = QuintoAndarLogger("sst.domains.salesforce.clean.transform")

# Event types produced by the API recovery / DLQ flows instead of the CDC stream.
# They are full-state snapshots rather than sparse deltas.
SNAPSHOT_EVENT_TYPES = ("RECOVERY",)

# Flags the row carrying the previous known state into the replay window. It is a
# seed, not an event, and never reaches the output.
BASELINE_COL = "is_baseline"

# Internal ordering column; excluded from the output like BASELINE_COL.
_RANK_COL = "_snapshot_rank"

# 0 for API snapshots, 1 for CDC stream events. Kept as SQL text, not a Column:
# a module-level Column would need an active SparkContext at import time, and both
# callers import this module before they build their session.
#
# Salesforce delivers commit_ts truncated to the second, so a snapshot and a stream
# event for the same record routinely collide on it, and snapshots carry a synthetic
# commit_number/sequence_number of 1 (domains/salesforce/api/transform.py) that cannot
# break that tie either. Within one second the snapshot sorts first: it is a
# full-state read, so a sparse stream event following it inherits every recovered
# value it does not carry itself — null keeps the last value, non-null overwrites.
# A null event_type falls through to 1, as it did when this was an isin() Column.
SNAPSHOT_RANK_EXPR = (
    "CASE WHEN event_type IN "
    f"({', '.join(repr(event) for event in SNAPSHOT_EVENT_TYPES)}) THEN 0 ELSE 1 END"
)

# Ascending replay order for the events of one id_record. commit_ts is the
# authoritative event time, _RANK_COL resolves the sub-second snapshot/stream
# collision, then commit_number and finally sequence_number — a position *within* a
# commit, so only meaningful once commit_number is equal. in_memory_cdc_udpate
# prefixes BASELINE_COL; _latest_row_for_record_id mirrors this descending.
EVENT_ORDER_COLS = ("commit_ts", _RANK_COL, "commit_number", "sequence_number")


def _latest_row_for_record_id(spark, records_id_df, target_table):
    base_ids = records_id_df.select("id_record").dropDuplicates(["id_record"])
    latest = spark.read.table(target_table)
    history = latest.join(F.broadcast(base_ids), "id_record", "right")

    # Descending mirror of the replay order, or the state this lookup calls
    # "latest" is not the state the replay would end on. The previous keys were
    # ``committed_at`` (derived from the already second-truncated commit_ts) and
    # ``sequence_number``, which left same-second events to be resolved by a
    # within-transaction position and dropped commit_number entirely.
    snapshot_rank = F.expr(SNAPSHOT_RANK_EXPR)
    order = [
        snapshot_rank.desc() if col == _RANK_COL else F.col(col).desc_nulls_last()
        for col in EVENT_ORDER_COLS
    ]
    w = Window.partitionBy("id_record").orderBy(*order)
    case_when = F.when(F.col("event_type").isNotNull(), F.lit("HISTORICAL")).otherwise(
        F.lit("MISSING")
    )
    return (
        history.withColumn("row", F.row_number().over(w))
        .withColumn("event_type", case_when)
        .where(F.col("row") == 1)
        .drop("row")
    )


@logger(exclude=["df"], exclude_return=True)
def search_for_latest_record(spark, df, target_table, filter_missing=True):
    has_create = check_for_create_partition(df)
    has_missing_create = has_create.where(~F.col("has_create")).limit(1).collect()
    df = df.withColumn("new_record", F.lit(True)).withColumn(BASELINE_COL, F.lit(False))
    if has_missing_create:
        logger.info(
            "m=_search_for_latest_record, msg= Looking for latest entry in target table"
        )
        if _table_exists(spark, target_table):
            latest = (
                _latest_row_for_record_id(
                    spark, has_create.where(~F.col("has_create")), target_table
                )
                .withColumn("new_record", F.lit(False))
                .withColumn(BASELINE_COL, F.lit(True))
            )
            logger.info(
                "m=_search_for_latest_record, msg= Returning latest entry from target table"
            )
            if filter_missing:
                missing_ids = (
                    latest.where(F.col("event_type") == "MISSING")
                    .select("id_record")
                    .distinct()
                )
                latest = latest.where(F.col("event_type") != "MISSING")
                df = df.join(F.broadcast(missing_ids), "id_record", "leftanti")
            return safe_column_union(df, latest)
        else:
            logger.info(
                "m=_search_for_latest_record, msg= Target table does not exists, failing job"
            )
            raise ValueError(f"Table {target_table} doesn't exists.")
    return df


def in_memory_cdc_udpate(df):
    ranked = df.withColumn(_RANK_COL, F.expr(SNAPSHOT_RANK_EXPR))

    order = [F.col(col).asc_nulls_first() for col in EVENT_ORDER_COLS]
    if BASELINE_COL in ranked.columns:
        # The baseline is the last known state, not an event, so it always seeds
        # the window whatever its commit_ts says. Ordering it by timestamp would
        # let a stream event sharing its second sort first and be conformed
        # against an empty window, nulling every column that event does not carry.
        order.insert(0, F.col(BASELINE_COL).desc())

    w = (
        Window.partitionBy("id_record")
        .orderBy(*order)
        .rowsBetween(Window.unboundedPreceding, 0)
    )
    # Control columns are excluded from both the passthrough and the carried
    # columns, so they never reach the output and column order is unchanged.
    cols = [
        col
        for col in ranked.columns
        if col
        not in [
            "id_record",
            "commit_number",
            "commit_ts",
            "sequence_number",
            "changed_field",
            BASELINE_COL,
            _RANK_COL,
        ]
    ]
    updated_cdc = ranked.select(
        "id_record",
        "commit_number",
        "commit_ts",
        "sequence_number",
        "changed_field",
        *[F.last(F.col(col), ignorenulls=True).over(w).alias(col) for col in cols],
    )

    delete_non_null_cols = [
        "id_record",
        "entity_name",
        "event_type",
        "transaction_key",
        "sequence_number",
        "commit_number",
        "commit_ts",
        "commit_user",
        "changed_field",
        "source_file",
        "committed_at",
        "new_record",
    ]

    return nullify_fields_on_delete(df=updated_cdc, non_null_cols=delete_non_null_cols)
