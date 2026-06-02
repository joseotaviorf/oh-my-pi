from argparse import ArgumentParser

from pyspark.sql import functions as F
from pyspark.sql.window import Window
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_fact_price_changes"
logger = QuintoAndarLogger(JOB_NAME)

PRICE_CHANGE_TABLE = "datalake_ebdb_pricing.listing_price_change"
PREDICTION_CHANGES_TABLE = "datalake_ebdb_pricing.listing_prediction_changes"
SUGGESTION_CHANGES_TABLE = "datalake_ebdb_pricing.house_suggestion_changes"


def get_affected_price_changes(spark, start_date, end_date):
    """
    Return all id_price_change values that need reprocessing in this batch.

    A price change needs reprocessing if any of the three source tables had
    activity in the date range that could alter its fact row:

    1. New price changes (ts_price_started in range):
       a new price change updates ts_price_ended of the immediately preceding
       price change in the source — which may belong to a different
       id_house_listing. To ensure that preceding record is reprocessed, we
       use (id_house, business_context) as the join key, fetching the full
       history across all listing versions.

    2. New predictions (ts_calculator_result_started in range):
       predictions are scoped to a specific listing version, so we use the
       narrower (id_house, id_house_listing, business_context) key here.

    3. New suggestions (ts_suggestion_started in range):
       the suggestion join key is (id_house, business_context), so ALL price
       changes for that house are included.
    """
    price_changes = spark.table(PRICE_CHANGE_TABLE)

    # New price changes: use house-level key so that ts_price_ended updates in
    # prior listing versions are correctly reprocessed.
    affected_houses_from_price = (
        price_changes.filter(
            F.to_date(F.col("ts_price_started")).between(start_date, end_date)
        )
        .select("id_house", "business_context")
        .distinct()
    )

    # New predictions: scoped to listing version.
    affected_listing_versions_from_prediction = (
        spark.table(PREDICTION_CHANGES_TABLE)
        .filter(
            F.to_date(F.col("ts_calculator_result_started")).between(
                start_date, end_date
            )
        )
        .select("id_house", "id_house_listing", "business_context")
        .distinct()
    )

    # New suggestions: house-level key (no id_house_listing in suggestion join).
    affected_houses_from_suggestion = (
        spark.table(SUGGESTION_CHANGES_TABLE)
        .filter(F.to_date(F.col("ts_suggestion_started")).between(start_date, end_date))
        .select("id_house", "business_context")
        .distinct()
    )

    return (
        price_changes.join(
            F.broadcast(affected_houses_from_price), ["id_house", "business_context"]
        )
        .select("id_price_change")
        .unionByName(
            price_changes.join(
                F.broadcast(affected_listing_versions_from_prediction),
                ["id_house", "id_house_listing", "business_context"],
            ).select("id_price_change")
        )
        .unionByName(
            price_changes.join(
                F.broadcast(affected_houses_from_suggestion),
                ["id_house", "business_context"],
            ).select("id_price_change")
        )
        .distinct()
    )


def build_fact_price_changes(spark, pri_df):
    """
    Build fact_price_changes for the given price changes.

    Step 1 — prediction CTE: for each price change, pick the earliest prediction
    whose calculator result started within the price validity window.

    Step 2 — outer query: for each price change, pick the latest suggestion
    whose start falls within the price validity window.

    DataFrame aliases (pri / pre / p / hsc) mirror the SQL table aliases, making
    join conditions readable without manual column prefixing.
    """
    # --- Step 1: resolve prediction per price change ---
    pri = pri_df.alias("pri")
    pre = spark.table(PREDICTION_CHANGES_TABLE).alias("pre")

    prediction_join_cond = (
        (F.col("pre.id_house") == F.col("pri.id_house"))
        & (F.col("pre.id_house_listing") == F.col("pri.id_house_listing"))
        & (F.col("pre.business_context") == F.col("pri.business_context"))
        & (F.col("pre.ts_calculator_result_started") >= F.col("pri.ts_price_started"))
        & (
            F.col("pre.ts_calculator_result_started")
            <= F.coalesce(F.col("pri.ts_price_ended"), F.current_timestamp())
        )
    )

    prediction_window = Window.partitionBy(F.col("pri.id_price_change")).orderBy(
        F.col("pre.ts_calculator_result_started"),
        F.coalesce(F.col("pre.ts_calculator_result_ended"), F.current_timestamp()),
    )

    prediction_df = (
        pri.join(pre, prediction_join_cond, "left")
        .withColumn("rn", F.row_number().over(prediction_window))
        .filter(F.col("rn") == 1)
        .select(
            F.col("pri.id_price_change").alias("sk_pricing"),
            F.coalesce(F.col("pre.id_prediction_change"), F.lit(-1)).alias(
                "sk_price_predicted"
            ),
            F.col("pri.id_house").alias("sk_house"),
            F.col("pri.id_house_listing").alias("sk_house_listing"),
            F.coalesce(F.col("pri.id_user_revision"), F.lit(-1)).alias("sk_user"),
            F.col("pri.days_with_pricing_scheme"),
            F.col("pri.business_context"),
            F.col("pri.ts_price_started"),
            F.col("pri.ts_price_ended"),
        )
    ).alias("p")

    # --- Step 2: resolve suggestion per price change ---
    hsc = spark.table(SUGGESTION_CHANGES_TABLE).alias("hsc")

    suggestion_join_cond = (
        (F.col("hsc.id_house") == F.col("p.sk_house"))
        & (F.col("hsc.business_context") == F.col("p.business_context"))
        & (F.col("p.ts_price_started") >= F.col("hsc.ts_suggestion_started"))
        & (
            F.col("p.ts_price_started")
            <= F.coalesce(F.col("hsc.ts_suggestion_ended"), F.current_timestamp())
        )
    )

    suggestion_window = Window.partitionBy(F.col("p.sk_pricing")).orderBy(
        F.col("hsc.ts_suggestion_started").desc(),
        F.coalesce(F.col("hsc.ts_suggestion_ended"), F.current_timestamp()).desc(),
    )

    return (
        prediction_df.join(hsc, suggestion_join_cond, "left")
        .withColumn("rn", F.row_number().over(suggestion_window))
        .filter(F.col("rn") == 1)
        .select(
            F.col("p.sk_pricing"),
            F.col("p.sk_price_predicted"),
            F.coalesce(F.col("hsc.id_suggestion_change"), F.lit(-1)).alias(
                "sk_price_suggested"
            ),
            F.col("p.sk_house"),
            F.col("p.sk_house_listing"),
            F.col("p.sk_user"),
            F.col("p.days_with_pricing_scheme"),
            F.col("p.ts_price_started"),
            F.col("p.ts_price_ended"),
            F.current_timestamp().alias("ts_load"),
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

    add_validation_target_args(parser)
    args = parser.parse_args()

    logger.info(
        f"m=__main__, environment={args.environment}, "
        f"database_name={args.database_name}, table_name={args.table_name}, "
        f"load_start_date={args.load_start_date}, load_end_date={args.load_end_date}, "
        f"msg=Starting {JOB_NAME}"
    )

    spark_client = SparkClient()
    spark = spark_client.conn

    start_date = F.lit(args.load_start_date).cast("date")
    end_date = F.lit(args.load_end_date).cast("date")

    affected_ids = get_affected_price_changes(spark, start_date, end_date).cache()

    affected_count = affected_ids.count()
    logger.info(f"m=__main__, affected_price_changes={affected_count:,}")

    if affected_count == 0:
        logger.warning(
            "m=__main__, msg=No affected price changes found in date range, skipping"
        )
    else:
        pri = (
            spark.table(PRICE_CHANGE_TABLE)
            .join(F.broadcast(affected_ids), ["id_price_change"])
            .select(
                "id_price_change",
                "id_house",
                "id_house_listing",
                "id_user_revision",
                "days_with_pricing_scheme",
                "business_context",
                "ts_price_started",
                "ts_price_ended",
            )
        )

        result_df = build_fact_price_changes(spark, pri)

        database_name = f"dw_{args.database_name}"
        prod_location = (
            f"s3://{args.datalake_bucket}/{args.database_name}/{args.table_name}"
        )
        write_database_name, write_table_name, write_location = (
            resolve_datalake_write_target(
                prod_database=database_name,
                prod_table=args.table_name,
                prod_location=prod_location,
                bucket=args.datalake_bucket,
                target_database=args.target_database_name,
                target_table=args.target_table_name,
            )
        )

        SparkMetastoreService(spark_client).create_database(write_database_name)

        full_table_name = f"{write_database_name}.{write_table_name}"
        s3_path = (
            f"{write_location}{write_table_name}"
            if write_location.endswith("/")
            else write_location
        )

        DeltaLoader().load_table(
            table_name=full_table_name,
            path=s3_path,
            source_df=result_df,
            merge_on=["sk_pricing"],
        )

        SparkMetastoreService(spark_client).refresh_table(
            write_database_name, write_table_name
        )
        logger.info(
            f"m=__main__, table={full_table_name}, msg=Load completed successfully"
        )

    affected_ids.unpersist()
