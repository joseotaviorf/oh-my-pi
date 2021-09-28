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
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from quintoandar_logger import QuintoAndarLogger
from quintoandar_sirena_api_client.consumers import CONSUMERS
from quintoandar_sirena_api_client.clients import SirenaClient

JOB_NAME = "load_sirena_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

SCHEMA = """
    id STRING NOT NULL,
    created STRING NOT NULL,
    account STRING NOT NULL,
    accountId STRING NOT NULL,
    group STRING NOT NULL,
    groupId STRING NOT NULL,
    initialGroup STRING,
    initialGroupId STRING,
    firstName STRING,
    label STRING,
    lastName STRING,
    category STRING COMMENT 'The unique name identifier of the prospect category',
    status STRING NOT NULL COMMENT 'Enum: "unclaimed" "new" "followUp" "processing" "archived"',
    nin ARRAY<
        STRUCT<
            id: STRING COMMENT 'Enum: "CUIT" "CUIL" "DNI" "CPF" "RUN" "RUT" "CURP" "RFC" "IMSS" "DNIC"',
            number: STRING COMMENT 'The NIN that corresponds to the lead'
        >
    >,
    userMade BOOLEAN,
    archivingReason STRING COMMENT 'When the prospect is archived this property contains the code of the reason why it was filed',
    phones ARRAY<STRING>,
    emails ARRAY<STRING>,
    contactMediums ARRAY<STRING>,
    additionalData STRING COMMENT 'Additional and private data of the prospect. Only returned when the scope prospects:readAdditionalData is authorized',
    merged BOOLEAN COMMENT 'If true, it means that the lead was merged with an existent prospect in Sirena',
    absenceMessage STRING COMMENT 'If message is present, it means that the target agent/s were not working and a absence message was configured for the group',
    leads ARRAY<
        STRUCT<
            priority: INTEGER COMMENT 'The priority of the Lead',
            created: STRING NOT NULL,
            createdBy: STRING,
            source: STRING NOT NULL,
            comments: STRING,
            utmSource: STRING NOT NULL,
            providerKey: STRING,
            company: STRING COMMENT 'The company indicated when the lead was sent to Sirena',
            store: STRING COMMENT 'The store indicated when the lead was sent to Sirena',
            agent: STRING COMMENT 'The agent indicated when the lead was sent to Sirena',
            type: STRING NOT NULL COMMENT 'Enum: "retail" "insurance" "realEstate" "vehicle" "savingPlan"',
            product: STRING
        >
    > NOT NULL,
    agent STRUCT<
        id: STRING NOT NULL,
        firstName: STRING NOT NULL,
        lastName: STRING NOT NULL,
        email: STRING,
        phone: STRING,
        appFields: STRING
    >,
    assigned STRING,
    nextReminder STRING,
    firstContactedAt STRING,
    sentWorkingHourMessage STRING
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
    consumer_prospects = CONSUMERS["prospects"](client=sirena_client)

    groups_list = consumer_groups.sync(flattened_key="id")
    agents_list = consumer_agents.sync(
        groups=groups_list, flattened_key="id", executor_type="thread", unique=True
    )
    results = consumer_prospects.sync(
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
