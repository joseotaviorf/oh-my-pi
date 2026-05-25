import ast
import logging
from argparse import ArgumentParser
from datetime import date, timedelta

from pyspark.sql import functions as F
from pyspark.sql.window import Window
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.metastore_services import SparkMetastoreService

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_buyer_funnel_users"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

EVENTS_TABLE = "datalake_amplitude_agents_app.agents_search_events"


def get_agents_search_events_state(dt_snapshot: date):
    """
    Get the daily aggregate of agents search events.
    """
    df = (
        spark.table(EVENTS_TABLE)
        .where(
            (F.col("year") == dt_snapshot.year)
            & (F.col("month") == dt_snapshot.month)
            & (F.col("day") == dt_snapshot.day)
        )
        .select("id_amplitude", "id_user", "ts_event", "business_context")
        .where(F.col("id_amplitude").isNotNull())
    )

    df = (
        df.groupBy("id_amplitude")
        .agg(
            F.max_by(
                F.when(F.col("id_user").isNotNull(), F.col("id_user")),
                F.col("ts_event"),
            ).alias("id_user"),
            F.min(F.when(F.col("id_user").isNotNull(), F.col("ts_event"))).alias(
                "ts_first_logged_activity"
            ),
            F.min(F.when(F.col("business_context") == "sale", F.col("ts_event"))).alias(
                "ts_first_sale_activity"
            ),
            F.min("ts_event").alias("ts_first_activity"),
            F.max("ts_event").alias("ts_latest_activity"),
            F.max(F.when(F.col("business_context") == "sale", F.col("ts_event"))).alias(
                "ts_latest_sale_activity"
            ),
        )
        .withColumn("dt_snapshot", F.lit(dt_snapshot))
        .withColumn("year", F.lit(dt_snapshot.year))
        .withColumn("month", F.lit(dt_snapshot.month))
        .withColumn("day", F.lit(dt_snapshot.day))
    )

    return df


def get_previous_state_for_ids(df_state, full_table_name, dt_snapshot):
    """
    Load the previous state for the ids that appear in the day aggregate.
    """
    df_ids = df_state.select("id_amplitude").distinct()

    df_previous_state = (
        spark.table(full_table_name)
        .select(
            "id_amplitude",
            "id_user",
            "ts_first_logged_activity",
            "ts_first_sale_activity",
            "ts_first_activity",
            "ts_latest_activity",
            "ts_latest_sale_activity",
            "dt_snapshot",
            "year",
            "month",
            "day",
        )
        .filter(F.col("dt_snapshot") < F.lit(dt_snapshot).cast("TIMESTAMP"))
        .join(df_ids, on="id_amplitude", how="inner")
    )

    w = Window.partitionBy("id_amplitude").orderBy(F.col("dt_snapshot").desc())
    df_previous_state = (
        df_previous_state.withColumn("rn", F.row_number().over(w))
        .where(F.col("rn") == 1)
        .drop("rn")
        .drop("year", "month", "day")
        .drop("dt_snapshot")
    )

    return df_previous_state


def get_minimum_timestamp(column_a, column_b):
    """
    Get the minimum timestamp between two columns, ignoring null values.
    """
    return (
        F.when(column_a.isNull(), column_b)
        .when(column_b.isNull(), column_a)
        .when(column_b < column_a, column_b)
        .otherwise(column_a)
    )


def get_maximum_timestamp(column_a, column_b):
    """
    Get the maximum timestamp between two columns, ignoring null values.
    """
    return (
        F.when(column_a.isNull(), column_b)
        .when(column_b.isNull(), column_a)
        .when(column_b > column_a, column_b)
        .otherwise(column_a)
    )


def compute_new_state(df_current_state, df_previous_state):
    """
    Compute the new state based on the current and previous state.
    """
    joined = df_current_state.alias("cs").join(
        df_previous_state.alias("ps"), on="id_amplitude", how="left"
    )

    df_new_state = joined.select(
        F.col("id_amplitude"),
        F.coalesce(F.col("cs.id_user"), F.col("ps.id_user")).alias("id_user"),
        get_minimum_timestamp(
            F.col("ps.ts_first_logged_activity"), F.col("cs.ts_first_logged_activity")
        ).alias("ts_first_logged_activity"),
        get_minimum_timestamp(
            F.col("ps.ts_first_sale_activity"), F.col("cs.ts_first_sale_activity")
        ).alias("ts_first_sale_activity"),
        get_minimum_timestamp(
            F.col("ps.ts_first_activity"), F.col("cs.ts_first_activity")
        ).alias("ts_first_activity"),
        get_maximum_timestamp(
            F.col("ps.ts_latest_activity"), F.col("cs.ts_latest_activity")
        ).alias("ts_latest_activity"),
        get_maximum_timestamp(
            F.col("ps.ts_latest_sale_activity"), F.col("cs.ts_latest_sale_activity")
        ).alias("ts_latest_sale_activity"),
        F.col("cs.dt_snapshot"),
        F.col("cs.year"),
        F.col("cs.month"),
        F.col("cs.day"),
    )

    return df_new_state


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="datalake_bucket")
    parser.add_argument("database_name", help="database_name")
    parser.add_argument("table_name", help="table_name")
    parser.add_argument("partitions", help="partitions")
    parser.add_argument("load_start_date", help="partitions")
    parser.add_argument("load_end_date", help="partitions")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    database_name = args.database_name
    table_name = args.table_name
    partitions = ast.literal_eval(args.partitions)
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date

    logger.info(
        f"""m=__main__, environment={environment},
        datalake_bucket={datalake_bucket}, database_name={database_name},
        table_name={table_name}, partitions={partitions}, 
        load_start_date={load_start_date}, load_end_date={load_end_date}
        msg=Load Buyer Funnel Users spark job running.
        """
    )

    dt_start = date.fromisoformat(load_start_date)
    dt_end = date.fromisoformat(load_end_date)

    dates_by_process = []
    dt_current = dt_start
    while dt_current <= dt_end:
        dates_by_process.append(dt_current)
        dt_current += timedelta(days=1)

    spark_client = SparkClient()
    loader = DeltaLoader()
    spark_metastore_service = SparkMetastoreService(spark_client)

    db_info = DatalakeMetastoreService.get_db_info(
        environment, database_name, datalake_bucket
    )
    database_name = db_info["db_enrich_databricks"]
    database_location = db_info["db_enrich_path"]
    spark_metastore_service.create_database(database_name)

    s3_path = f"{database_location}{table_name}"
    full_table_name = f"{database_name}.{table_name}"

    for dt_snapshot in dates_by_process:
        df_state = get_agents_search_events_state(dt_snapshot)
        df_previous_state = get_previous_state_for_ids(
            df_state, full_table_name, dt_snapshot
        )
        df_new_state = compute_new_state(df_state, df_previous_state)

        if df_new_state.limit(1).count():
            loader.load_table(
                table_name=full_table_name,
                path=s3_path,
                partition_by=partitions,
                source_df=df_new_state,
                merge_on=["id_amplitude", "dt_snapshot"],
            )
            spark_metastore_service.refresh_table(database_name, table_name)
        else:
            logger.error(
                f"""msg=Error while getting data for buyer_funnel_users table.
          m=__main__, dt_snapshot={dt_snapshot},
          The Dataframe is empty!
        """
            )
