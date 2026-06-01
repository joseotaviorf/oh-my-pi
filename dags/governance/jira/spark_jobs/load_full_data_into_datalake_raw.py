import json
import logging
from argparse import ArgumentParser

from quintoandar_jira_api_client.clients import JiraClient
from quintoandar_jira_api_client.consumers import CONSUMERS
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkDataFrameService,
    SparkTableStorageFormat,
)
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.json_service import JsonService
from bietlejuice.services.metastore_services import SparkMetastoreService

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_full_data_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def sync_data(username, token, server, endpoint_name):
    """
    Method for calling the JiraClient and the specific consumer
    :param username: username for authorization
    :param token: api token for authorization
    :param server: name of the Jira account
    :param endpoint_name: name of the Jira endpoint
    :return: Json list of returned records
    """

    jira_client = JiraClient(username=username, token=token, server=server)

    consumer_instance = CONSUMERS[endpoint_name](jira_client)
    return consumer_instance.sync()


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the API")
    parser.add_argument("load_start_date", help="execution date in str format")
    parser.add_argument("load_end_date", help="end execution date in str format")
    parser.add_argument("endpoint_name", help="endpoint to call the API")
    parser.add_argument("partitions", help="Partition columns name")

    add_validation_target_args(parser)
    args = parser.parse_args()

    environment = args.environment
    source = args.source
    datalake_bucket = args.datalake_bucket
    endpoint_name = args.endpoint_name

    logger.info(
        f"m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket}, "
        f"endpoint_name={endpoint_name}, msg=Starting spark job..."
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    json_credentials = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key=APIEnum.JIRA)
    credentials = json.loads(json_credentials)
    json_list = sync_data(
        username=credentials["username"],
        token=credentials["token"],
        server=credentials["server"],
        endpoint_name=endpoint_name,
    )
    json_data = JsonService.transform_json_list_terms(json_list)

    spark_client = SparkClient()
    df = spark_client.create_dataframe(json_data)

    df = (
        SparkDataFrameService()
        .input(df)
        .convert_array_type_to_json()
        .optimize_partition(
            1500000
        )  # 1.5kk records will give us files with around 1GB (json)
        .output()
    )

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=database_name,
            prod_table=endpoint_name,
            prod_location=database_location,
            bucket=datalake_bucket,
            target_database=args.target_database_name,
            target_table=args.target_table_name,
        )
    )

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    metastore_service = SparkMetastoreService(spark_client)
    metastore_service.create_database(write_database_name)

    s3_loader = S3Loader()
    s3_loader.load_full_table(
        df=df,
        database_name=write_database_name,
        table_name=write_table_name,
        format_options=format_options,
        database_location=write_location,
    )

    spark_metastore_loader = SparkMetastoreLoader(metastore_service)
    spark_metastore_loader.update_metastore(
        df,
        write_database_name,
        write_table_name,
        format_options,
        write_location,
    )
