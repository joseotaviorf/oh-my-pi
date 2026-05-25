import json
import logging
from argparse import ArgumentParser
from datetime import datetime

from pyspark.sql.types import StructType
from quintoandar_chattermill_api_client.clients import ChattermillClient
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkDataFrameService,
    SparkTableStorageFormat,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_chattermill_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("raw_table_name", help="table name in the raw layer")
    parser.add_argument("execution_date", help="execution date in str format")
    parser.add_argument("partition_cols")
    parser.add_argument("table_details")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    raw_table_name = args.raw_table_name
    execution_date = args.execution_date
    partition_cols = json.loads(args.partition_cols)

    table_details = json.loads(args.table_details)
    endpoint = table_details.get("endpoint")
    block_list_campaing = table_details.get("block_list_campaing")
    schema = json.loads(table_details.get("schema"))
    schema = StructType.fromJson(schema)

    logger.info(
        f"""
            m={JOB_NAME}, environment={environment}, source={source}, endpoint={endpoint},
            execution_date={execution_date}, datalake_bucket={datalake_bucket},
            raw_table_name={raw_table_name}, msg=print spark jobs args"
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    json_credentials = dbutils.secrets.get(
        scope=DATABRICKS_SCOPE, key=APIEnum.CHATTERMILL
    )
    credentials = json.loads(json_credentials)
    chattermill_client = ChattermillClient(
        project_name=credentials["project_name"], auth=credentials["auth"]
    )

    spark_client = SparkClient()

    # API response
    api_response = chattermill_client.get_data(
        endpoint=endpoint, from_date=execution_date.replace("-", "")
    )

    for row in api_response:
        if "user_attributes" in row:
            row["user_attributes"] = json.dumps(row.get("user_attributes"))
        if "tags" in row:
            row["tags"] = json.dumps(row.get("tags"))
        if "phrases" in row:
            row["phrases"] = json.dumps(row.get("phrases"))

    api_response = list(
        filter(
            lambda item: (
                json.loads(item["user_attributes"])["campaign"]["value"]
                not in block_list_campaing
            ),
            api_response,
        )
    )

    if api_response:
        df = spark_client.create_dataframe(api_response, schema=schema)
        dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
        df = df.coalesce(1)
        df = (
            SparkDataFrameService()
            .input(df)
            .create_year_month_day_columns_from_date(dt_execution)
            .output()
        )

        datalake_info = DatalakeMetastoreService.get_db_info(
            environment, source, datalake_bucket
        )
        spark_metastore_service = SparkMetastoreService(spark_client)
        database_name = datalake_info["db_raw_databricks"]
        spark_metastore_service.create_database(database_name)

        database_location = datalake_info["db_raw_path"]
        format_options = SparkTableStorageFormat.DEFAULT_RAW

        # loaders
        s3_loader = S3Loader()
        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{raw_table_name}",
            format_options=format_options,
            partitions=partition_cols,
        )
        spark_metastore_loader.update_metastore(
            df,
            database_name,
            raw_table_name,
            format_options,
            database_location,
            partition_cols,
            force_recreate=True,
        )
        spark_metastore_service.create_new_partitions_from_df(
            database_name=database_name,
            table_name=raw_table_name,
            df=df,
            partition_cols=partition_cols,
        )
        spark_metastore_service.refresh_table(database_name, raw_table_name)
