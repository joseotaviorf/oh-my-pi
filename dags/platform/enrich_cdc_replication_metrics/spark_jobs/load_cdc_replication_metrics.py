from collections import defaultdict
import logging
import json
import re
from argparse import ArgumentParser, Namespace
import pyspark.sql.functions as F
from pyspark.sql import DataFrame
from quintoandar_logger import QuintoAndarLogger
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.messaging_services.gchat_service import GChatService
from bietlejuice.services.messaging_services.message import Message
from bietlejuice.base.spark.base_spark import BaseDBUtils
from bietlejuice.base.notification.gchat_webhooks_enum import GchatWebhooksEnum


THRESHOLD_IN_SECONDS = 1200
JOB_NAME = "load_cdc_replication_metrics"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")


def parse_arguments() -> Namespace:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("datalake_bucket")
    parser.add_argument("partition_cols")
    parser.add_argument("start_date")
    parser.add_argument("end_date")
    parser.add_argument("schema")
    parser.add_argument("gchat_channel_customizations")

    return parser.parse_args()


def get_df_with_metrics(df: DataFrame, table: str, database_name: str) -> DataFrame:
    """
    Generates a df with cdc metrics: count_of_hard_deletes and timestamp_diff_in_seconds. 
    Quantify hard_delete operations (op_cdc = "d")
    and uses the difference in seconds from the ts_cdc_transaction(CDC replication) 
    and the ts_database_transaction (Database operation) to identify if the table is
    being replicated with delays.
    """
    logger.info(
        "m=get_df_with_metrics, msg=Extracting cdc metrics from the Transactional layer..."
    )

    df.createOrReplaceTempView("temp_df")
    df_metrics = spark.sql(
        f"""
                                SELECT
                                    '{table}' AS table_name,
                                    '{database_name}' AS database_name,
                                    COUNT_IF(op_cdc = 'd') AS count_of_hard_deletes,
                                    MAX(UNIX_TIMESTAMP(ts_cdc_transaction) - UNIX_TIMESTAMP(ts_database_transaction)) AS timestamp_diff_in_seconds,
                                    year, month, day
                                FROM temp_df 
                                GROUP BY year, month, day
                            """
    )
    return df_metrics


def send_messages(
    df_tables_delayed: DataFrame,
    start_date: str,
    end_date: str,
    gchat_channel_customizations: dict,
) -> None:
    """
    Send the alert messages to a default Gchat Channel and, optionally, to a custom channel.
    """
    logger.info("m=send_message, msg=Formatting the alert messages...")

    base_dbutils = BaseDBUtils()
    dbutils = base_dbutils.get_dbutils()
    channel_key_message_mapping = get_formatted_message_content_per_channel(
        df_tables_delayed, start_date, end_date, gchat_channel_customizations
    )

    logger.info("m=send_message, msg=Sending the alert messages...")
    for channel_key, message_content in channel_key_message_mapping.items():
        channel = dbutils.secrets.get(scope="quintoandar", key=channel_key)
        message = Message(message_content, channel)
        GChatService.send_message(message)


def get_formatted_message_content_per_channel(
    df_tables_delayed: DataFrame,
    start_date: str,
    end_date: str,
    gchat_channel_customizations: dict,
) -> dict:
    """
    Returns a dictionary mapping each channel key to its corresponding message content
    """
    channel_key_message_mapping = defaultdict(str)
    default_channel_key = GchatWebhooksEnum.GCHAT_CDC_METRICS
    for row in df_tables_delayed.collect():
        if row["timestamp_diff_in_seconds"] < THRESHOLD_IN_SECONDS:
            continue
        schema = re.search(r"datalake_(\w+)_transactional", row["database_name"]).group(
            1
        )
        table_message = f"Table: {row['database_name']}.{row['table_name']}, Delay in seconds: {row['timestamp_diff_in_seconds']}\n"

        # We want to send the message to the default channel AND the custom channel
        channel_key_message_mapping[default_channel_key] += table_message
        if schema in gchat_channel_customizations:
            channel_key = gchat_channel_customizations[schema]
            channel_key_message_mapping[channel_key] += table_message

    message_template = """
⚠️ *Delays were found between Database Transaction and DBZ Replication* ⚠️
    
*The following tables are being replicated by debezium with a delay*
Date Interval: {start_date} - {end_date}
{tables_message}
There might be a problem with the source database, check the monitoring Dashboards.
    """.strip()

    return {
        channel_key: message_template.format(
            start_date=start_date, end_date=end_date, tables_message=tables_message
        )
        for channel_key, tables_message in channel_key_message_mapping.items()
    }


def trigger_gchat_alerts(
    df: DataFrame, start_date: str, end_date: str, gchat_channel_customizations: dict
) -> None:
    """
  Checks if the timestamp_diff_in_seconds column reaches the threshold.
  If so, calls the function that sends the Gchat Alert
  """
    logger.info(
        "m=trigger_gchat_alerts, msg=Checking if the timestamp_diff_in_seconds reached the threshold..."
    )
    df_tables_delayed = get_tables_to_alert_delay(df)
    if not df_tables_delayed.isEmpty():
        send_messages(
            df_tables_delayed, start_date, end_date, gchat_channel_customizations
        )


def get_tables_to_alert_delay(df_metrics: DataFrame) -> DataFrame:
    """
    Returns a DataFrame with the tables that have delays above the threshold in the CDC replication
    """
    return (
        df_metrics.filter(F.col("timestamp_diff_in_seconds") >= THRESHOLD_IN_SECONDS)
        .select("database_name", "table_name", "timestamp_diff_in_seconds")
        .groupBy("database_name", "table_name")
        .agg(F.max("timestamp_diff_in_seconds").alias("timestamp_diff_in_seconds"))
    )


def get_metrics_df(start_date: str, end_date: str) -> DataFrame:
    """
    Returns a df with cdc metrics from all transactional tables that will be used to load the final table
    """

    logger.info("m=get_metrics_df, msg=Generating the df_metrics for all tables...")
    is_first_iteration = True
    database_names = [
        database.name
        for database in spark.catalog.listDatabases()
        if database.name.endswith("_transactional")
        and not database.name.endswith("test_transactional")
    ]

    for database_name in database_names:
        tables = [table.name for table in spark.catalog.listTables(database_name)]
        for table in tables:
            logger.info(
                f"m=get_metrics_df, msg=Generating table {database_name}.{table} metrics based on start_date={start_date} and end_date={end_date}..."
            )
            df = spark.sql(
                f"""
                    SELECT
                        op_cdc, ts_database_transaction, ts_cdc_transaction, year, month, day
                    FROM {database_name}.{table}
                    WHERE make_date(year, month, day) BETWEEN '{start_date}' AND '{end_date}'
                """
            )

            df_metrics = get_df_with_metrics(df, table, database_name)

            if is_first_iteration:
                df_all_tables = df_metrics
                is_first_iteration = False
            else:
                df_all_tables = df_all_tables.union(df_metrics)

    return df_all_tables


def main() -> None:
    args = parse_arguments()
    datalake_bucket = args.datalake_bucket
    partition_cols = json.loads(args.partition_cols)
    start_date = args.start_date
    end_date = args.end_date
    schema = args.schema
    gchat_channel_customizations = json.loads(args.gchat_channel_customizations)

    loader = DeltaLoader()
    destination_table_path = (
        f"s3://{datalake_bucket}/enrich/{schema}/cdc_replication_metrics"
    )
    destination_table_name = f"datalake_{schema}.cdc_replication_metrics"

    logger.info(
        f"""m={JOB_NAME}, datalake_bucket={datalake_bucket},
        start_date={start_date}, end_date={end_date}, partition_cols={partition_cols}, schema={schema}"""
        "msg=Starting spark job..."
    )

    df = get_metrics_df(start_date, end_date)
    df.cache()
    if df.isEmpty():
        logger.info(
            f"""
            m=__main__, msg=Metrics Dataframe is empty, there is no changes to propagate.
            """
        )
        return

    loader.load_table(
        destination_table_name,
        path=destination_table_path,
        partition_by=partition_cols,
        source_df=df,
    )

    trigger_gchat_alerts(df, start_date, end_date, gchat_channel_customizations)


if __name__ == "__main__":
    main()
