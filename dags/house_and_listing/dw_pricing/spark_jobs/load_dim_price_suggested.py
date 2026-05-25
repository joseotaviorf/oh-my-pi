from argparse import ArgumentParser

from pyspark.sql import functions as F
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_dim_price_suggested"
logger = QuintoAndarLogger(JOB_NAME)

SOURCE_TABLE = "datalake_ebdb_pricing.house_suggestion_changes"


def get_affected_suggestions(spark, start_date, end_date):
    """
    Get suggestion changes that were updated in the date range.
    Uses ts_suggestion_started for incremental filtering.
    """
    return (
        spark.table(SOURCE_TABLE)
        .filter(F.to_date(F.col("ts_suggestion_started")).between(start_date, end_date))
        .select("id_house_suggestion", "business_context")
        .distinct()
    )


def build_dim_price_suggested(spark, affected_suggestions):
    """
    Build dim_price_suggested for affected suggestions.
    Contains only descriptive attributes.
    """
    source_df = spark.table(SOURCE_TABLE)

    filtered_df = source_df.join(
        F.broadcast(affected_suggestions),
        ["id_house_suggestion", "business_context"],
        "inner",
    )

    return filtered_df.select(
        F.col("id_suggestion_change").alias("sk_price_suggested"),
        "rule",
        "suggestion_certainty",
        "business_context",
        F.current_timestamp().alias("ts_load"),
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

    affected_suggestions = get_affected_suggestions(spark, start_date, end_date)

    affected_count = affected_suggestions.count()
    logger.info(f"m=__main__, affected_suggestions={affected_count:,}")

    if affected_count == 0:
        logger.warning(
            "m=__main__, msg=No affected suggestions found in date range, skipping"
        )
    else:
        result_df = build_dim_price_suggested(spark, affected_suggestions)

        database_name = f"dw_{args.database_name}"

        SparkMetastoreService(spark_client).create_database(database_name)

        full_table_name = f"{database_name}.{args.table_name}"
        s3_path = f"s3://{args.datalake_bucket}/{args.database_name}/{args.table_name}"

        DeltaLoader().load_table(
            table_name=full_table_name,
            path=s3_path,
            source_df=result_df,
            merge_on=["sk_price_suggested"],
        )

        SparkMetastoreService(spark_client).refresh_table(
            database_name, args.table_name
        )
        logger.info(
            f"m=__main__, table={full_table_name}, msg=Load completed successfully"
        )
