import json
import logging
from argparse import ArgumentParser

from pyspark import Row
from pyspark.sql.types import (
    StructType,
    StringType,
    StructField,
    LongType,
    ArrayType,
    MapType,
)
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
JOB_NAME = "load_active_employee_dependents_to_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def fetch_convenia_active_employee_dependents(host, token):
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

    active_employee_dependents = CONSUMERS["DependentsConsumer"](client=client)

    results = active_employee_dependents.sync(
        list(active_employees.select("id").toPandas()["id"])
    )

    return results


def create_df_from_employee_dependents(results, spark_client, token_name):
  rows = []
  for dependent in results:
    rows.append(
      Row(
        id=str(dependent["id"]),
        employee_id=str(dependent["employee_id"]),
        name=str(dependent["name"]),
        last_name=str(dependent["last_name"]),
        email=str(dependent["email"]),
        birth_date=str(dependent["birth_date"]),
        cpf=str(dependent["cpf"]),
        mother_name=str(dependent["mother_name"]),
        dependent_relation=str(dependent["dependent_relation"]),
        dependent_relation_description=str(dependent["dependent_relation_description"]),
        relation_esocial_id=str(dependent["relation_esocial_id"]),
        ir=str(dependent["ir"]),
        foreigner=str(dependent["foreigner"]),
        family_salary=str(dependent["family_salary"]),
        description=str(dependent["description"]),
        phone=str(dependent["phone"]),
        benefits = [{"":""}]
        if len(dependent["benefits"]) == 0
        else dependent["benefits"],
        # benefits=ArrayType(dependent["benefits"]),
        source=token_name
      )
    )
  if not rows:
    return create_df_schema()
  else:
    return spark_client.create_dataframe(rows)



def create_df_schema():
  columns = StructType(
    [
      StructField('id', StringType(), True), 
      StructField('employee_id', StringType(), True), 
      StructField('name', StringType(), True), 
      StructField('last_name', StringType(), True), 
      StructField('email', StringType(), True), 
      StructField('birth_date', StringType(), True), 
      StructField('cpf', StringType(), True), 
      StructField('mother_name', StringType(), True), 
      StructField('dependent_relation', StringType(), True), 
      StructField('dependent_relation_description', StringType(), True), 
      StructField('relation_esocial_id', StringType(), True), 
      StructField('ir', StringType(), True), 
      StructField('foreigner', StringType(), True), 
      StructField('family_salary', StringType(), True), 
      StructField('description', StringType(), True), 
      StructField('phone', StringType(), True), 
      StructField('benefits', ArrayType(MapType(StringType(), StringType(), True), True), True),
      StructField('source', StringType(), True)
    ]
  )
  return spark.createDataFrame(data=[], schema=columns)


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

    for token_name, details in credentials.items():
        host = details["host"]
        api_token = details["token"]

        dependents_result = fetch_convenia_active_employee_dependents(host, api_token)
        json_data = []
        for employee in dependents_result:
            for dependent in employee:
                json_data.append(dependent)

        spark_client = SparkClient()
        df = create_df_from_employee_dependents(
            json_data, spark_client, token_name
        )
        result = df.union(result)

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
        df=result,
        s3_path=f"{database_location}{table_name}",
        format_options=format_options,
    )
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)
    spark_metastore_loader.update_metastore(
        result, database_name, table_name, format_options, database_location
    )
    metastore_service.refresh_table(database_name, table_name)
