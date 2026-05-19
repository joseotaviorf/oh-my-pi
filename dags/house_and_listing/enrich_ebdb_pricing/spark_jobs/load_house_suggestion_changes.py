from argparse import ArgumentParser

from pyspark.sql import DataFrame, functions as F
from pyspark.sql.window import Window

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.metastore_services import SparkMetastoreService

from quintoandar_logger import QuintoAndarLogger

JOB_NAME = "load_house_suggestion_changes"
logger = QuintoAndarLogger(JOB_NAME)

SOURCE_TABLE = "datalake_ebdb_clean.house_price_suggestion_historical"
SOURCE_COLUMNS = [
    "id",
    "id_cdc_transaction",
    "id_prediction",
    "id_house",
    "business_context",
    "rule",
    "suggestion_certainty",
    "deal_objective_lower_anchor",
    "deal_objective_upper_anchor",
    "lower_bound_limit",
    "upper_bound_limit",
    "suggested_lower_bound_price",
    "suggested_price",
    "suggested_upper_bound_price",
    "ts_updated",
    "ts_cdc_transaction",
    "year",
    "month",
    "day",
]

CHANGE_COLUMNS = [
    "rule",
    "suggestion_certainty",
    "deal_objective_lower_anchor",
    "deal_objective_upper_anchor",
    "lower_bound_limit",
    "upper_bound_limit",
    "suggested_lower_bound_price",
    "suggested_price",
    "suggested_upper_bound_price",
]

HOUSE_WINDOW = (
    Window
    .partitionBy("id_house", "business_context")
    .orderBy("ts_updated", "id_cdc_transaction")
)


def _get_candidates(start_date, end_date):
    """Houses with any CDC activity in the date range (partition-pruned)."""
    return (
        spark.table(SOURCE_TABLE)
        .filter(
            F.make_date(F.col("year"), F.col("month"), F.col("day"))
            .between(start_date, end_date)
        )
        .select("id_house", "business_context")
        .distinct()
    )


def _build_all_changes(candidates):
    """
    Read full history for candidate houses, detect real suggestion changes
    via a single hash comparison, and return only changed rows.
    """
    source_df = spark.table(SOURCE_TABLE).select(*SOURCE_COLUMNS)
    history = source_df.join(
        F.broadcast(candidates), ["id_house", "business_context"], "inner"
    )

    change_hash = F.xxhash64(*[F.col(c) for c in CHANGE_COLUMNS])

    return (
        history
        .withColumn("_hash", change_hash)
        .withColumn("_prev_hash", F.lag("_hash").over(HOUSE_WINDOW))
        .filter(
            (F.col("_prev_hash").isNull())  # first record per house
            | (F.col("_hash") != F.col("_prev_hash"))
        )
        .drop("_hash", "_prev_hash")
    )


def _get_affected_houses(all_changes, start_date, end_date):
    """Subset of houses whose real changes fall within the load window."""
    return (
        all_changes
        .filter(
            F.make_date(F.col("year"), F.col("month"), F.col("day"))
            .between(start_date, end_date)
        )
        .select("id_house", "business_context")
        .distinct()
    )


def _apply_window_columns(changes_df):
    """Add change_number, suggestion time boundaries, and surrogate key."""
    window_by_house_day = (
        Window
        .partitionBy("id_house", "business_context", F.to_date("ts_updated"))
        .orderBy("ts_updated", "id_cdc_transaction")
    )

    return (
        changes_df
        .withColumn("change_number", F.row_number().over(HOUSE_WINDOW))
        .withColumn("ts_suggestion_ended", F.lead("ts_updated").over(HOUSE_WINDOW))
        .withColumn("_ts_next_same_day", F.lead("ts_updated").over(window_by_house_day))
        .withColumn("is_last_suggestion", F.col("ts_suggestion_ended").isNull())
        .withColumn("is_last_suggestion_of_day", F.col("_ts_next_same_day").isNull())
        .withColumn("id_suggestion_change", F.abs(F.xxhash64(F.col("id"), F.col("id_cdc_transaction"))))
        .withColumnRenamed("id", "id_house_suggestion")
        .withColumnRenamed("ts_updated", "ts_suggestion_started")
        .drop("id_cdc_transaction", "ts_cdc_transaction", "year", "month", "day", "_ts_next_same_day")
        .select(
            "id_suggestion_change",
            "id_house_suggestion",
            "id_prediction",
            "id_house",
            "business_context",
            "rule",
            "suggestion_certainty",
            "deal_objective_lower_anchor",
            "deal_objective_upper_anchor",
            "lower_bound_limit",
            "upper_bound_limit",
            "suggested_lower_bound_price",
            "suggested_price",
            "suggested_upper_bound_price",
            "change_number",
            "is_last_suggestion",
            "is_last_suggestion_of_day",
            "ts_suggestion_started",
            "ts_suggestion_ended",
        )
    )


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="Environment: forno/prod")
    parser.add_argument("datalake_bucket", help="Datalake bucket")
    parser.add_argument("database_name", help="Database base name")
    parser.add_argument("dag_name", help="DAG name")
    parser.add_argument("table_name", help="Target table name")
    parser.add_argument("load_start_date", help="Load start date (YYYY-MM-DD)")
    parser.add_argument("load_end_date", help="Load end date (YYYY-MM-DD)")
    parser.add_argument("run_mode", help="Run mode: prod/dev")

    args = parser.parse_args()

    logger.info(
        f"m=__main__, environment={args.environment}, "
        f"database_name={args.database_name}, table_name={args.table_name}, "
        f"load_start_date={args.load_start_date}, load_end_date={args.load_end_date}, "
        f"msg=Starting {JOB_NAME}"
    )

    start_date = F.lit(args.load_start_date).cast("date")
    end_date = F.lit(args.load_end_date).cast("date")

    candidates = _get_candidates(start_date, end_date)
    all_changes = _build_all_changes(candidates)
    all_changes.persist()

    try:
        affected_houses = _get_affected_houses(all_changes, start_date, end_date)
        affected_count = affected_houses.count()
        logger.info(f"m=__main__, affected_houses={affected_count:,}")

        if affected_count == 0:
            logger.warning(
                "m=__main__, msg=No affected houses found in date range, skipping"
            )
        else:
            result_df = _apply_window_columns(
                all_changes.join(
                    F.broadcast(affected_houses),
                    ["id_house", "business_context"],
                    "inner",
                )
            )

            spark_client = SparkClient()
            db_info = DatalakeMetastoreService.get_db_info(
                args.environment, args.database_name, args.datalake_bucket
            )
            database_name = db_info["db_enrich_databricks"]
            database_location = db_info["db_enrich_path"]

            SparkMetastoreService(spark_client).create_database(database_name)

            full_table_name = f"{database_name}.{args.table_name}"
            s3_path = f"{database_location}{args.table_name}"

            DeltaLoader().load_table(
                table_name=full_table_name,
                path=s3_path,
                source_df=result_df,
                merge_on=["id_suggestion_change"],
            )

            SparkMetastoreService(spark_client).refresh_table(
                database_name, args.table_name
            )
            logger.info(
                f"m=__main__, table={full_table_name}, "
                f"msg=Load completed successfully"
            )
    finally:
        all_changes.unpersist()
