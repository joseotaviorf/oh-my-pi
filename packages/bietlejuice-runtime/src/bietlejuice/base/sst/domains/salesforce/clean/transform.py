import pyspark.sql.functions as F
from pyspark.sql import Window
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.sst.core.utils.common import _table_exists, safe_column_union
from bietlejuice.base.sst.core.utils.transforms import nullify_fields_on_delete
from bietlejuice.base.sst.domains.salesforce.clean.check import (
    check_for_create_partition,
)

logger = QuintoAndarLogger("sst.domains.salesforce.clean.transform")


def _latest_row_for_record_id(
    spark, records_id_df, target_table, sort_cols=["committed_at", "sequence_number"]
):
    base_ids = records_id_df.select("id_record").dropDuplicates(["id_record"])
    latest = spark.read.table(target_table)
    history = latest.join(F.broadcast(base_ids), "id_record", "right")

    order_expr = [F.col(c).desc_nulls_last() for c in sort_cols]
    w = Window.partitionBy("id_record").orderBy(*order_expr)
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
    df = df.withColumn("new_record", F.lit(True))
    if has_missing_create:
        logger.info(
            "m=_search_for_latest_record, msg= Looking for latest entry in target table"
        )
        if _table_exists(spark, target_table):
            latest = _latest_row_for_record_id(
                spark, has_create.where(~F.col("has_create")), target_table
            ).withColumn("new_record", F.lit(False))
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
    w = (
        Window.partitionBy("id_record")
        .orderBy("commit_ts", "commit_number", "sequence_number")
        .rowsBetween(Window.unboundedPreceding, 0)
    )
    cols = [
        col
        for col in df.columns
        if col not in ["id_record", "commit_number", "commit_ts", "sequence_number"]
    ]
    updated_cdc = df.select(
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
        "commited_at",
        "new_record",
    ]

    return nullify_fields_on_delete(df=updated_cdc, non_null_cols=delete_non_null_cols)
