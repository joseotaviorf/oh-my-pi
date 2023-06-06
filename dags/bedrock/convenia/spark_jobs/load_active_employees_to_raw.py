import json
import logging
from argparse import ArgumentParser

from pyspark import Row
from pyspark.sql.types import StructType, StringType, StructField
from quintoandar_logger import QuintoAndarLogger
from quintoandar_convenia_api_client.clients import ConveniaClient
from quintoandar_convenia_api_client.consumers import CONSUMERS

from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.api.api_enum import APIEnum

from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
)

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_active_employees_to_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def fetch_convenia_active_employees(host, token):
    client = ConveniaClient(api_token=token, api_base_url=host)

    active_employees = CONSUMERS["ActiveEmployees"](client=client)

    results = active_employees.sync()

    return results


def create_df_from_active_employees(results, spark_client, token_name):
    rows = []
    for employee in results:
        rows.append(
            Row(
                id=employee["id"],
                name=employee["name"],
                last_name=employee["last_name"],
                email=employee["email"],
                dt_hiring=employee["hiring_date"],
                intern=str(employee["intern"]),
                foreign=str(employee["foreign"]),
                source=token_name,
            )
        )

    if not rows:
        rows = create_df_schema()
        return rows
    else:
        return spark_client.create_dataframe(rows)


def create_df_schema():
    columns = StructType(
        [
            StructField("id", StringType(), True),
            StructField("name", StringType(), True),
            StructField("last_name", StringType(), True),
            StructField("email", StringType(), True),
            StructField("dt_hiring", StringType(), True),
            StructField("intern", StringType(), True),
            StructField("foreign", StringType(), True),
            StructField("source", StringType(), True),
        ]
    )

    # Create a dataframe with expected schema
    result = spark.createDataFrame(data=[], schema=columns)

    return result


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the API")
    parser.add_argument("table_name", help="table name to be created")

    args = parser.parse_args()

    environment = args.environment
    source = args.source
    datalake_bucket = args.datalake_bucket
    table_name = args.table_name

    logger.info(
        f"m=load_active_employees_to_raw, environment={environment}, source={source}, datalake_bucket={datalake_bucket}, "
        f"table_name={table_name}, msg=Starting spark job..."
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    json_credentials = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key=APIEnum.CONVENIA)
    credentials = json.loads(json_credentials)

    result = create_df_schema()

    for token_name, details in credentials.items():
        host = details.get("host")
        api_token = details.get("token")

        active_employees_response = fetch_convenia_active_employees(host, api_token)
        spark_client = SparkClient()
        df = create_df_from_active_employees(
            active_employees_response, spark_client, token_name
        )
        result = df.union(result)

    df = result
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
        df=df, s3_path=f"{database_location}{table_name}", format_options=format_options
    )
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)
    spark_metastore_loader.update_metastore(
        df, database_name, table_name, format_options, database_location
    )
    metastore_service.refresh_table(database_name, table_name)
