import logging
from argparse import ArgumentParser
from datetime import datetime

from bietlejuice.jobs.composer.base.api.api_enum import APIEnum
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import (
    BaseDBUtils,
    SparkDataFrameService,
    SparkTableStorageFormat,
    sc,
)
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader
from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from quintoandar_logger import QuintoAndarLogger
from quintoandar_sirena_api_client.consumers import CONSUMERS
from quintoandar_sirena_api_client.clients import SirenaClient

JOB_NAME = "load_sirena_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

SCHEMA = """
    id STRING NOT NULL COMMENT 'Enum: "whatsapp" "facebook"',
    agentId STRING COMMENT 'Communication Channel Id',
    agent STRUCT<
        id: STRING NOT NULL,
        firstName: STRING NOT NULL,
        lastName: STRING NOT NULL,
        email: STRING,
        phone: STRING,
        appFields: STRING
    >,
    prospectId STRING,
    createdAt STRING NOT NULL,
    dueAt STRING,
    startedAt STRING,
    finishedAt STRING,
    status STRING,
    proactive BOOLEAN,
    via STRING,
    output STRUCT<
        comment: STRING,
        reminder: STRING,
        visitScheduled: STRING,
        question: STRUCT<
            id: STRING COMMENT 'The ID of the associated question',
            providerId: STRING COMMENT 'The ID of the question in the provider',
            threadTitle: STRING COMMENT 'Title of the thread in the provider',
            threadUrl: STRING COMMENT 'Url of the thread in the provider',
            question: STRING NOT NULL COMMENT 'Question text',
            answer: STRING COMMENT 'Answer text to the question, if the status property is "opened" this property will be ignored',
            delivered: BOOLEAN COMMENT 'Check this answer as delivered',
            cancelReason: STRING COMMENT 'Reason wherefore the system can not deliver an answer, if the status property is not "cancelled" this property will be ignored'
        >,
        message: STRUCT<
            providerId: STRING COMMENT 'The ID of the call in the provider',
            template: STRING,
            templateConfig: STRING,
            content: STRING COMMENT 'Text message',
            delivered: BOOLEAN COMMENT 'Check message as delivered',
            sender: STRING COMMENT 'Sender reference',
            recipient: STRING COMMENT 'Recipient reference',
            attachment: STRUCT<
                type: STRING COMMENT 'Enum: "FILE" "IMAGE" "AUDIO" "VIDEO"',
                url: STRING
            >,
            via: STRING NOT NULL COMMENT 'Enum: "whatsApp" "sms" "email" "facebook"'
        >,
        rejectionReason: STRING,
        proposal: STRUCT<
            firstCreatedAt: STRING,
            items: ARRAY<
                STRUCT<
                    price: STRING,
                    concept: STRING
                >
            >,
            status: STRING
        >,
        status: STRING,
        visitSuccessful: BOOLEAN,
        callSuccessful: BOOLEAN,
        webAction: STRING,
        transferedTo: STRUCT<
            id: STRING NOT NULL,
            firstName: STRING NOT NULL,
            lastName: STRING NOT NULL,
            email: STRING,
            phone: STRING
        >,
        transferedToAgentId: STRING,
        transferedToGroupId: STRING,
        response: STRING,
        conversations: ARRAY<
            STRUCT<
                id: STRING,
                channe: STRING,
                providerName: STRING,
                threadTitle: STRING,
                threadSubtitle: STRING,
                threadTumbnail: STRING
            >
        >,
        customEvent: STRING
    >
"""


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name")
    parser.add_argument("execution_date")
    args = parser.parse_args()

    environment = args.environment
    source = args.source
    datalake_bucket = args.datalake_bucket
    table_name = args.table_name
    execution_date = args.execution_date
    created_after = f"{execution_date}T00:00:00.000Z"
    created_before = f"{execution_date}T23:59:59.999Z"
    partition_cols = ["year", "month", "day"]

    logger.info(
        f"m={JOB_NAME}, "
        f"environment={environment}, "
        f"source={source}, "
        f"datalake_bucket={datalake_bucket}, "
        f"msg=Spark job arguments"
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    s3_loader = S3Loader()
    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, source, datalake_bucket
    )

    file_type = SparkTableStorageFormat.DEFAULT_RAW
    filesystem_path = datalake_info["db_raw_path"]
    database_name = datalake_info["db_raw_databricks"]
    spark_metastore_service.create_database(database_name)

    api_token = dbutils.secrets.get(scope="quintoandar", key=APIEnum.SIRENA)

    sirena_client = SirenaClient(api_token=api_token)
    consumer_groups = CONSUMERS["groups"](client=sirena_client)
    consumer_agents = CONSUMERS["agents"](client=sirena_client)
    consumer_interactions = CONSUMERS["interactions"](client=sirena_client)

    groups_list = consumer_groups.sync(flattened_key="id")
    agents_list = consumer_agents.sync(
        groups=groups_list, flattened_key="id", executor_type="thread", unique=True
    )
    results = consumer_interactions.sync(
        agents=agents_list,
        executor_type="spark",
        executor_spark_context=sc,
        created_after=created_after,
        created_before=created_before,
    )

    if results:
        df = spark_client.create_dataframe(results, schema=SCHEMA)
        df = (
            SparkDataFrameService()
            .input(df)
            .create_year_month_day_columns_from_date(
                datetime.strptime(execution_date, "%Y-%m-%d")
            )
            .output()
        )

        s3_loader.load_df(
            df=df,
            s3_path=f"{filesystem_path}{table_name}",
            format_options=file_type,
            partitions=partition_cols,
        )

        spark_metastore_loader.update_metastore(
            df=df,
            database_name=database_name,
            table_name=table_name,
            format_options=file_type,
            database_location=filesystem_path,
            partitions=partition_cols,
            force_recreate=False,
        )

        spark_metastore_service.create_new_partitions_from_df(
            database_name=database_name,
            table_name=table_name,
            df=df,
            partition_cols=partition_cols,
        )

        spark_metastore_service.refresh_table(database_name, table_name)
