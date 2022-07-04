import json
import logging
from argparse import ArgumentParser

from pyspark import Row
from datetime import datetime, timedelta

from quintoandar_logger import QuintoAndarLogger
from quintoandar_onetrust_api_client.clients import OnetrustClient
from quintoandar_onetrust_api_client.consumers import CONSUMERS
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader
from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.api.api_enum import APIEnum
from bietlejuice.jobs.composer.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
    SparkDataFrameService,
)

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_full_data_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def fetch_onetrust_audit(auth_headers, start_date, end_date):
    client = OnetrustClient(auth_headers=auth_headers)

    audit = CONSUMERS["Audit"](client=client)

    audit_results = audit.sync(start_date, end_date)

    return audit_results


def create_df_from_audit(results, spark_client):
    rows = []
    for records in results:
        for login in records:
            rows.append(
                Row(
                    username=str(login.get("userName")),
                    id_address=str(login.get("ipAddress")),
                    user_agent=str(login.get("userAgentString")),
                    created_date=str(login.get("createDT")),
                    status=str(login.get("status")),
                    user_id=str(login.get("userId")),
                )
            )

    return spark_client.create_dataframe(rows)


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the API")
    parser.add_argument("table_name", help="table name to be created")
    parser.add_argument("execution_date", help="execution date in str format")

    args = parser.parse_args()

    environment = args.environment
    source = args.source
    datalake_bucket = args.datalake_bucket
    table_name = args.table_name
    execution_date = datetime.strftime(
        datetime.strptime(args.execution_date, "%Y-%m-%d"), "%Y-%m-%dT%H:%M:%SZ"
    )

    start_date = datetime.strftime(
        datetime.strptime(execution_date, "%Y-%m-%dT%H:%M:%SZ")
        - timedelta(363),  # The API only store this records for 365 days
        "%Y-%m-%dT%H:%M:%SZ",
    )

    logger.info(
        f"m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket}, "
        f"table_name={table_name}, msg=Starting spark job..."
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    json_credentials = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key=APIEnum.ONETRUST)
    credentials = json.loads(json_credentials)

    audit_response = fetch_onetrust_audit(
        credentials["auth_headers"], start_date=start_date, end_date=execution_date
    )

    spark_client = SparkClient()
    df = create_df_from_audit(audit_response, spark_client)

    df = SparkDataFrameService().input(df).convert_array_type_to_json().output()

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    metastore_service = SparkMetastoreService(spark_client)
    metastore_service.create_database(database_name)

    s3_loader = S3Loader()
    s3_loader.load_df(
        df=df, s3_path=f"{database_location}{table_name}", format_options=format_options
    )

    spark_metastore_loader = SparkMetastoreLoader(metastore_service)
    spark_metastore_loader.update_metastore(
        df, database_name, table_name, format_options, database_location
    )
    metastore_service.refresh_table(database_name, table_name)
