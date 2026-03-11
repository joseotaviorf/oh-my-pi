from bietlejuice.base.sst.domains.salesforce.clean.check import (
    check_for_create_partition,
)
from bietlejuice.base.sst.core.utils.common import _table_exists, safe_column_union
from quintoandar_logger import QuintoAndarLogger
from pyspark.sql import Window


import pyspark.sql.functions as F

logger = QuintoAndarLogger("sst.domains.salesforce.clean.transform")


def _latest_row_for_record_id(
    spark, records_id_df, target_table, sort_col="committed_at"
):
    base_ids = records_id_df.select("record_id").dropDuplicates(["record_id"])
    latest = spark.read.table(target_table)
    history = latest.join(F.broadcast(base_ids), "record_id", "right")
    w = Window.partitionBy("record_id").orderBy(F.col(sort_col).desc_nulls_last())
    return (
        history.withColumn("row", F.row_number().over(w))
        .withColumn(
            "event_type", F.lit("HISTORICAL")
        )  # This will be dropped downstream
        .where(F.col("row") == 1)
        .drop("row")
    )


@logger(exclude=["df"], exclude_return=True)
def search_for_latest_record(spark, df, target_table):
    has_create = check_for_create_partition(df)
    missing_create_count = has_create.where(~F.col("has_create")).count()
    df = df.withColumn("new_record", F.lit(True))
    if missing_create_count > 0:
        logger.info(
            f"m=_search_for_latest_record, msg= Missing create event for {missing_create_count} records"
        )
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
            return safe_column_union(df, latest)
        else:
            logger.info(
                "m=_search_for_latest_record, msg= Target table does not exists, failing job"
            )
            raise ValueError(
                f"Table {target_table} doesn't exists. {missing_create_count} UPDATES/DELETE rows found even without a previous record"
            )
    return df


def in_memory_cdc_udpate(df):
    w = (
        Window.partitionBy("record_id")
        .orderBy("commit_ts", "commit_number", "sequence_number")
        .rowsBetween(Window.unboundedPreceding, 0)
    )
    cols = [
        col
        for col in df.columns
        if col not in ["record_id", "commit_number", "commit_ts", "sequence_number"]
    ]
    return df.select(
        "record_id",
        "commit_number",
        "commit_ts",
        "sequence_number",
        *[F.last(F.col(col), ignorenulls=True).over(w).alias(col) for col in cols],
    )
