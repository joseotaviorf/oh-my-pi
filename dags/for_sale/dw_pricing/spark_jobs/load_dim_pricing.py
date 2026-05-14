from argparse import ArgumentParser

from pyspark.sql import functions as F

from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.metastore_services import SparkMetastoreService

from quintoandar_logger import QuintoAndarLogger

JOB_NAME = "load_dim_pricing"
logger = QuintoAndarLogger(JOB_NAME)

SOURCE_TABLE = "datalake_ebdb_pricing.listing_price_change"


def get_affected_price_changes(spark, start_date, end_date):
    """
    Return all id_price_change values that need reprocessing in this batch.

    Filtering only by ts_price_started would miss price changes whose
    is_last_price or is_last_price_of_day flags were updated in the source
    because a newer price change was created for the same house in the date
    range. The flags are maintained at the id_house level in the source: a new
    price change — even from a different id_house_listing — flips is_last_price
    to false for every prior price change of that house.

    Strategy: find every (id_house, business_context) that had a new price
    change in the range, then reprocess ALL historical price changes for those
    houses across all listing versions.
    """
    price_changes = spark.table(SOURCE_TABLE)

    affected_houses = (
        price_changes
        .filter(F.to_date(F.col("ts_price_started")).between(start_date, end_date))
        .select("id_house", "business_context")
        .distinct()
    )

    return (
        price_changes
        .join(F.broadcast(affected_houses), ["id_house", "business_context"])
        .select("id_price_change")
        .distinct()
    )


def build_dim_pricing(spark, affected_price_changes):
    """
    Build dim_pricing for affected price changes.
    Contains only descriptive pricing attributes.
    """
    return (
        spark.table(SOURCE_TABLE)
        .join(F.broadcast(affected_price_changes), ["id_price_change"])
        .select(
            F.col("id_price_change").alias("sk_pricing"),
            "price",
            "previous_price",
            "last_price_variation",
            "first_price_variation",
            "change_number",
            "change_type",
            "business_context",
            "is_last_price",
            "is_last_price_of_day",
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
        logger.warning("m=__main__, msg=No affected price changes found in date range, skipping")
    else:
        result_df = build_dim_pricing(spark, affected_ids)

        database_name = f"dw_{args.database_name}"

        SparkMetastoreService(spark_client).create_database(database_name)

        full_table_name = f"{database_name}.{args.table_name}"
        s3_path = f"s3://{args.datalake_bucket}/{args.database_name}/{args.table_name}"

        DeltaLoader().load_table(
            table_name=full_table_name,
            path=s3_path,
            source_df=result_df,
            merge_on=["sk_pricing"],
        )

        SparkMetastoreService(spark_client).refresh_table(database_name, args.table_name)
        logger.info(f"m=__main__, table={full_table_name}, msg=Load completed successfully")

    affected_ids.unpersist()
