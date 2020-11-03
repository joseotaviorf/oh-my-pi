import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.service import ServiceEnum
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import SparkDataFrameService
from bietlejuice.jobs.composer.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.service_clients.pubsub import (
    PubSubSubscriberSyncPullClient,
)
from bietlejuice.jobs.composer.consumers.service_consumers.pubsub import (
    PubSubSubscriberSyncPullConsumer,
)
from bietlejuice.jobs.composer.services.json_service import JsonService
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService


DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_firestore_audit_into_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

MAX_RETRIES = 3
CHUNK_SIZE = 500


def get_messages_with_retries(pubsub_consumer, retry):
    messages, ack_ids = pubsub_consumer.get_messages()

    # Pubsub can return 0 messages even when there are messages in subscription.
    if not messages and retry < MAX_RETRIES:
        messages, ack_ids = get_messages_with_retries(pubsub_consumer, retry + 1)

    return messages, ack_ids


def get_messages_in_chunks(pubsub_consumer):
    final_messages = []
    final_ack_ids = []

    while len(final_messages) <= CHUNK_SIZE:
        messages, ack_ids = get_messages_with_retries(pubsub_consumer, 0)

        if not messages:
            logger.info(
                f"m=get_messages_in_chunks, pubsub_consumer={pubsub_consumer}, msg=All messages have been consumed!"
            )
            break

        final_messages.extend(messages)
        final_ack_ids.extend(ack_ids)

    return final_messages, final_ack_ids


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("env")
    parser.add_argument("source")
    parser.add_argument("datalake_bucket")
    parser.add_argument("project_id", help="project id from GCP")
    parser.add_argument("pubsub_credentials_path")
    parser.add_argument("subscription_id")
    parser.add_argument("table_name")
    args = parser.parse_args()

    environment = args.env
    source = args.source
    datalake_bucket = args.datalake_bucket
    project_id = args.project_id
    pubsub_credentials_path = args.pubsub_credentials_path
    subscription_id = args.subscription_id
    table_name = args.table_name

    logger.info(
        f"""
            m={JOB_NAME}, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
            project_id={project_id}, pubsub_credentials_path={pubsub_credentials_path},
            subscription_id={subscription_id}, table_name={table_name}, msg=Starting spark job..."
        """
    )

    partition_cols = ["year", "month", "day"]

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    json_credentials = dbutils.secrets.get(
        scope=DATABRICKS_SCOPE, key=ServiceEnum.PUBSUB.value
    )
    # PubSub Client expects a json file path containing the credentials
    dbutils.fs.put(
        file=pubsub_credentials_path, contents=json_credentials, overwrite=True
    )

    spark_client = SparkClient()
    pubsub_client = PubSubSubscriberSyncPullClient(project_id, subscription_id)
    pubsub_consumer = PubSubSubscriberSyncPullConsumer(pubsub_client)

    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, source, datalake_bucket
    )
    spark_metastore_service = SparkMetastoreService(spark_client)
    database_name = datalake_info["db_raw_databricks"]
    spark_metastore_service.create_database(database_name)

    database_location = datalake_info["db_raw_path"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    subscription_is_empty = False
    while not subscription_is_empty:
        messages, ack_ids = get_messages_in_chunks(pubsub_consumer)

        if not messages:
            break

        if len(messages) < CHUNK_SIZE:
            subscription_is_empty = True

        messages = JsonService.transform_json_list_terms(messages)
        df = spark_client.create_dataframe(messages)

        df = (
            SparkDataFrameService()
            .input(df)
            .create_year_month_day_columns_from_dataframe_column("timestamp")
            .optimize_partition(200000)
            .output()
        )

        s3_loader.load_df(
            df=df,
            s3_path=database_location + table_name,
            format_options=format_options,
            partitions=partition_cols,
            write_mode="append",
        )

        spark_metastore_loader.update_metastore(
            df,
            database_name,
            table_name,
            format_options,
            database_location,
            partition_cols,
            force_recreate=False,
        )

        spark_metastore_service.create_new_partitions_from_df(
            database_name=database_name,
            table_name=table_name,
            df=df,
            partition_cols=partition_cols,
        )

        pubsub_client.acknowledge_messages(ack_ids)
        spark_metastore_service.refresh_table(database_name, table_name)
