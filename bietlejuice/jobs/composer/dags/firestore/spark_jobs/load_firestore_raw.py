from argparse import ArgumentParser
from google.api_core.retry import Retry, exponential_sleep_generator
from google.cloud.pubsub_v1 import SubscriberClient
from tempfile import NamedTemporaryFile
from time import sleep
import json
import os

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.api import APIEnum
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import SparkDataFrameService
from bietlejuice.jobs.composer.base.spark import BaseDBUtils, SparkTableStorageFormat

from bietlejuice.jobs.composer.services.json_service import JsonService
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)


JOB_NAME = "load_firestore_raw"

MAX_EMPTY_RETRIES = 3
RETRY_TIMEOUT = 60
MAX_MESSAGES = 300
ACK_MESSAGES_CHUNK_SIZE = 300

logger = QuintoAndarLogger(JOB_NAME)


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("subscription_id")
    parser.add_argument("table_name")
    args = parser.parse_args()

    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    subscription_id = args.subscription_id
    table_name = args.table_name

    logger.info(
        f"""
            m={JOB_NAME}, environment={environment}, source={source},
            datalake_bucket={datalake_bucket}, subscription_id={subscription_id},
            table_name={table_name}, msg=Starting spark job..."
        """
    )

    config_service = ConfigurationService(source)
    credentials_env_var = config_service.get_config("credentials_env_var")
    project_id = config_service.get_config("project_id")
    raw_partition_cols = config_service.get_config("raw_partition_cols")

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    json_credentials = dbutils.secrets.get(scope="quintoandar", key=APIEnum.PUBSUB)

    temp_file = NamedTemporaryFile(suffix=".json", mode="a+")
    temp_file.write(json_credentials)
    temp_file.flush()

    os.environ[credentials_env_var] = temp_file.name

    subscriber_client = SubscriberClient()
    subscription_path = subscriber_client.subscription_path(project_id, subscription_id)

    with subscriber_client:
        ack_ids = []
        messages = []
        empty_messages_attempt = 1
        exp_sleep_gen = exponential_sleep_generator(initial=3, maximum=30)

        while empty_messages_attempt <= MAX_EMPTY_RETRIES:
            response = subscriber_client.pull(
                request={
                    "subscription": subscription_path,
                    "max_messages": MAX_MESSAGES,
                },
                retry=Retry(deadline=RETRY_TIMEOUT),
            )

            if not len(response.received_messages):
                time_to_wait = next(exp_sleep_gen)

                logger.info(
                    f"m=__main__, msg=No messages received in attempt {empty_messages_attempt}."
                )
                if empty_messages_attempt < MAX_EMPTY_RETRIES:
                    logger.info(
                        f"m=__main__, msg=Waiting for {time_to_wait} seconds until next attempt..."
                    )
                    sleep(time_to_wait)

                empty_messages_attempt += 1

                continue

            for received_message in response.received_messages:
                logger.info(
                    "m=__main__, msg=Received message published at {} after {} attempts.".format(
                        received_message.message.publish_time,
                        received_message.delivery_attempt or 0,
                    )
                )

                ack_ids.append(received_message.ack_id)
                messages.append(json.loads(received_message.message.data))

        if messages:
            datalake_info = DatalakeMetastoreService.get_db_info(
                environment, source, datalake_bucket
            )
            spark_client = SparkClient()
            spark_metastore_service = SparkMetastoreService(spark_client)
            database_name = datalake_info["db_raw_databricks"]
            spark_metastore_service.create_database(database_name)

            database_location = datalake_info["db_raw_path"]
            format_options = SparkTableStorageFormat.DEFAULT_RAW

            s3_loader = S3Loader()
            spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

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
                partitions=raw_partition_cols,
                write_mode="append",
            )

            spark_metastore_loader.update_metastore(
                df,
                database_name,
                table_name,
                format_options,
                database_location,
                raw_partition_cols,
                force_recreate=False,
            )

            spark_metastore_service.create_new_partitions_from_df(
                database_name=database_name,
                table_name=table_name,
                df=df,
                partition_cols=raw_partition_cols,
            )

            for i in range(0, len(ack_ids), ACK_MESSAGES_CHUNK_SIZE):
                subscriber_client.acknowledge(
                    request={
                        "subscription": subscription_path,
                        "ack_ids": ack_ids[i : i + ACK_MESSAGES_CHUNK_SIZE],
                    }
                )

            logger.info(
                "m=__main__, msg=Received and acknowledged {} messages from {}.".format(
                    len(ack_ids), subscription_id
                )
            )
        else:
            logger.info(
                f"m=__main__, msg=No messages were received from {subscription_id}."
            )

    temp_file.close()
