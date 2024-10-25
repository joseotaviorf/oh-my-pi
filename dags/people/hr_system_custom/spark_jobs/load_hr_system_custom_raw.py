import json
import requests
import argparse
from tenacity import retry, stop_after_attempt
from pyspark.sql.functions import current_timestamp

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader

JOB_NAME = "load_hr_system_custom_to_raw"
logger = QuintoAndarLogger(JOB_NAME)
DATABRICKS_SCOPE = "people"


@retry(stop=stop_after_attempt(3))
def get_data(url, token):
    logger.info(f"m={JOB_NAME}, msg=Getting data from url: {url}")
    url = f"{url}/ic/api/integration/v1/flows/rest/RECUPERARDADOSFUNCIONARIOPORMATR/1.0/hcm/funcionario/matricula"
    headers = {"Authorization": f"Basic {token}"}
    response = requests.request("GET", url, headers=headers)
    response_json = response.json()
    response_data = response_json["colaborador"]
    return response_data


def load_raw(
    spark_client,
    df,
    environment,
    source,
    datalake_bucket,
    table_name,
):
    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    logger.info(
        f"m={JOB_NAME}, msg=Creating database in Spark Metastore if not exists..."
    )
    metastore_service = SparkMetastoreService(spark_client)
    metastore_service.create_database(database_name)
    s3_loader = S3Loader()
    s3_loader.load_df(
        df=df,
        s3_path=f"{database_location}{table_name}",
        format_options=format_options,
    )
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)
    spark_metastore_loader.update_metastore(
        df=df,
        database_name=database_name,
        table_name=table_name,
        format_options=format_options,
        force_recreate=True,
        database_location=database_location,
    )
    metastore_service.refresh_table(database_name, table_name)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("table_name", help="table_name of the table")
    args = parser.parse_args()
    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()
    json_credentials = dbutils.secrets.get(
        scope=DATABRICKS_SCOPE, key=APIEnum.HR_SYSTEM_CUSTOM
    )
    credentials = json.loads(json_credentials)
    url = credentials["url"]
    token = credentials["token"]

    logger.info(
        f"m={JOB_NAME}, environment={environment}, source={source}, datalake_bucket={datalake_bucket}, "
        f"table_name={table_name}, msg=Starting spark job..."
    )
    response_data = get_data(url, token)
    spark_client = SparkClient()
    df = spark_client.create_dataframe(response_data)
    df = df.withColumn("ts_load", current_timestamp())
    df = df.dropDuplicates()
    load_raw(
        spark_client,
        df,
        environment,
        source,
        datalake_bucket,
        table_name,
    )
