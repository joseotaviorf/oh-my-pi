import json
import logging
from argparse import ArgumentParser

from pyspark import Row
from pyspark.sql.types import StructType, StringType, StructField, LongType
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
JOB_NAME = "load_active_employee_details_to_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def fetch_convenia_active_employee_details(host, token):
    client = ConveniaClient(api_token=token, api_base_url=host)

    active_employees = CONSUMERS["ActiveEmployees"](client=client)

    active_employees_results = active_employees.sync()

    rows = []
    for employee in active_employees_results:
        rows.append(Row(id=employee["id"]))

    if not rows:
        active_employees = create_df_schema()
    else:
        spark_client = SparkClient()
        active_employees = spark_client.create_dataframe(rows)

    active_employee_details = CONSUMERS["EmployeeDetails"](client=client)

    results = active_employee_details.sync(
        list(active_employees.select("id").toPandas()["id"])
    )

    return results


def create_df_from_active_employee_details(results, spark_client):
    rows = []
    for employee in results:
        rows.append(
            Row(
                id=str(employee["id"]),
                name=str(employee["name"]),
                last_name=str(employee["last_name"]),
                email=str(employee["email"]),
                hiring_date=str(employee["hiring_date"]),
                salary=str(employee["salary"]),
                alternative_email=str(employee["alternative_email"]),
                phone=str(employee["phone"]),
                cellphone=str(employee["cellphone"]),
                registration=str(employee["registration"]),
                gender=str(employee["gender"]),
                birth_date=str(employee["birth_date"]),
                natural_from_state_uf=str(employee["natural_from_state_uf"]),
                natural_from_city_name=str(employee["natural_from_city_name"]),
                marital_status_id=str(employee["marital_status_id"]),
                first_job=str(employee["first_job"]),
                gender_identity_id=str(employee["gender_identity_id"]),
                gender_identity=str(employee["gender_identity"]),
                relationship=str(employee["relationship"]),
                ethnicity=str(employee["ethnicity"]),
                documents=str(employee["documents"]),
                department=str(employee["department"]),
                job=str(employee["job"]),
                dismissal=str(employee["dismissal"]),
                supervisor=str(employee["supervisor"]),
                address=str(employee["address"]),
                cost_center=str(employee["cost_center"]),
                salary_type=str(employee["salary_type"]),
                benefits=str(employee["benefits"]),
                custom_fields=str(employee["custom_fields"]),
                time_tracking=str(employee["time_tracking"]),
                educations=str(employee["educations"]),
                experience_period=str(employee["experience_period"]),
                emergency_contacts=str(employee["emergency_contacts"]),
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
            StructField("hiring_date", StringType(), True),
            StructField("salary", LongType(), True),
            StructField("alternative_email", StringType(), True),
            StructField("phone", StringType(), True),
            StructField("cellphone", StringType(), True),
            StructField("registration", StringType(), True),
            StructField("gender", StringType(), True),
            StructField("birth_date", StringType(), True),
            StructField("natural_from_state_uf", StringType(), True),
            StructField("natural_from_city_name", StringType(), True),
            StructField("marital_status_id", StringType(), True),
            StructField("first_job", StringType(), True),
            StructField("gender_identity_id", StringType(), True),
            StructField("gender_identity", StringType(), True),
            StructField("relationship", StringType(), True),
            StructField("ethnicity", StringType(), True),
            StructField("documents", StringType(), True),
            StructField("department", StringType(), True),
            StructField("job", StringType(), True),
            StructField("dismissal", StringType(), True),
            StructField("supervisor", StringType(), True),
            StructField("address", StringType(), True),
            StructField("cost_center", StringType(), True),
            StructField("salary_type", StringType(), True),
            StructField("benefits", StringType(), True),
            StructField("custom_fields", StringType(), True),
            StructField("time_tracking", StringType(), True),
            StructField("educations", StringType(), True),
            StructField("experience_period", StringType(), True),
            StructField("emergency_contacts", StringType(), True),
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

        convenia_active_employee_details_result = fetch_convenia_active_employee_details(
            host, api_token
        )

        spark_client = SparkClient()
        df = create_df_from_active_employee_details(
            convenia_active_employee_details_result, spark_client
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
