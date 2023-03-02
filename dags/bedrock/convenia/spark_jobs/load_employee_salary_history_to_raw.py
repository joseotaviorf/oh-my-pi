import json
import logging
from argparse import ArgumentParser

from pyspark import Row
from pyspark.sql.types import LongType, StructType, StringType, StructField
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
    SparkDataFrameService,
)

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_employee_salary_history_to_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def fetch_convenia_employee_salary_history(host, token):
    client = ConveniaClient(api_token=token, api_base_url=host)

    active_employees = CONSUMERS["ActiveEmployees"](client=client)

    active_employees_results = active_employees.sync()

    rows = []
    for employee in active_employees_results:
        rows.append(Row(id=employee["id"]))

    spark_client = SparkClient()
    active_employees = spark_client.create_dataframe(rows)

    employee_salary_history = CONSUMERS["SalaryHistory"](client=client)

    results = employee_salary_history.sync(
        list(active_employees.select("id").toPandas()["id"])
    )

    return results


def create_df_from_employee_salary_history(results, spark_client):
    rows = []
    for employee in results:
        for details in employee:
            rows.append(
                Row(
                    id=str(details["id"]),
                    salary=details["salary"],
                    relationship_id=str(details["relationship_id"]),
                    relationship=str(details["relationship"]),
                    department_id=str(details["department_id"]),
                    department=str(details["department"]),
                    job_description_id=str(details["job_description_id"]),
                    job=str(details["job"]),
                    cost_center_id=str(details["cost_center_id"]),
                    cost_center=str(details["cost_center"]),
                    motive_id=str(details["motive_id"]),
                    motive=str(details["motive"]),
                    date_from=str(details["date_from"]),
                    date_to=str(details["date_to"]),
                    is_active=str(details["is_active"]),
                    description=str(details["description"]),
                    created_at=str(details["created_at"]),
                    updated_at=str(details["updated_at"]),
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
            StructField("salary", LongType(), True),
            StructField("relationship_id", StringType(), True),
            StructField("relationship", StringType(), True),
            StructField("department_id", StringType(), True),
            StructField("department", StringType(), True),
            StructField("job_description_id", StringType(), True),
            StructField("job", StringType(), True),
            StructField("cost_center_id", StringType(), True),
            StructField("cost_center", StringType(), True),
            StructField("motive_id", StringType(), True),
            StructField("motive", StringType(), True),
            StructField("date_from", StringType(), True),
            StructField("date_to", StringType(), True),
            StructField("is_active", StringType(), True),
            StructField("description", StringType(), True),
            StructField("created_at", StringType(), True),
            StructField("updated_at", StringType(), True),
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
        f"m={JOB_NAME}, environment={environment}, source={source}, datalake_bucket={datalake_bucket}, "
        f"table_name={table_name}, msg=Starting spark job..."
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    json_credentials = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key=APIEnum.CONVENIA)
    credentials = json.loads(json_credentials)

    result = create_df_schema()

    for item, details in credentials.items():
        host = details["host"]
        api_token = details["token"]

        convenia_employee_salary_history_result = fetch_convenia_employee_salary_history(
            host, api_token
        )
        spark_client = SparkClient()
        df = create_df_from_employee_salary_history(
            convenia_employee_salary_history_result, spark_client
        )
        result = df.union(result)

    df = SparkDataFrameService().input(result).convert_array_type_to_json().output()
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
