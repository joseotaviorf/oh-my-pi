import ast
import logging

from argparse import ArgumentParser
from quintoandar_braze_api_client.clients import BrazeClient
from quintoandar_braze_api_client.factories import EndpointFactory

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat, BaseDBUtils, sc


JOB_NAME = "load_braze_details_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def _schema_enforcement(identifier: str, results: list):
  try:
    if identifier == 'canvas':
      logger.info("Creating DataFrame for 'canvas' identifier")
      df = spark.createDataFrame(
        [
          {
            "created_at": str(row['created_at']),
            "updated_at": str(row['updated_at']),
            "name": str(row['name']),
            "description": str(row['description']),
            "archived": str(row['archived']),
            "draft": str(row['draft']),
            "enabled": str(row['enabled']),
            "schedule_type": str(row['schedule_type']),
            "first_entry": str(row['first_entry']),
            "last_entry": str(row['last_entry']),
            "channels": str(row['channels']),
            "variants": str(row['variants']),
            "tags": str(row['tags']),
            "teams": str(row['teams']),
            "steps": str(row['steps']),
            "canvas_id": str(row['canvas_id'])
          } for row in results
        ]
      )
    elif identifier == 'campaign':
      logger.info("Creating DataFrame for 'campaign' identifier")
      df = spark.createDataFrame(
        [
          {
            "created_at": str(row['created_at']),
            "updated_at": str(row["updated_at"]),
            "name": str(row["name"]),
            "description": str(row["description"]),
            "archived": str(row["archived"]),
            "enabled": str(row["enabled"]),
            "draft": str(row["draft"]),
            "schedule_type": str(row["schedule_type"]),
            "channels": str(row["channels"]),
            "first_sent": str(row["first_sent"]),
            "last_sent": str(row["last_sent"]),
            "tags": str(row["tags"]),
            "teams": str(row["teams"]),
            "messages": str(row["messages"]),
            "conversion_behaviors": str(row["conversion_behaviors"]),
            "campaign_id": str(row["campaign_id"])
          } for row in results
        ]
      )
  except Exception as exception:
      logging.error(f"Fail to transform data. Schema error:{exception}")
      raise exception

  logger.info("Returning DataFrame for context")
  return df


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("app_group")
    parser.add_argument("identifiers")
    args = parser.parse_args()

    environment = args.environment
    source = args.source
    datalake_bucket = args.datalake_bucket
    app_group = args.app_group
    identifiers = ast.literal_eval(args.identifiers)

    logger.info(
        f"""m={JOB_NAME}, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
        app_group={app_group}, identifiers={identifiers}"""
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

    api_token = dbutils.secrets.get(
        scope="quintoandar", key=getattr(APIEnum, f"BRAZE_{app_group.upper()}")
    )
    instance = "US-03"
    endpoint = "details"

    braze_client = BrazeClient(api_token=api_token, instance=instance)
    factory = EndpointFactory(braze_client)

    for identifier in identifiers:

      table_name = f"{identifier}_{endpoint}_{app_group}"
      list_consumer = factory.build(identifier, "list")
      consumer = factory.build(identifier, endpoint)

      id_list = list_consumer.sync(reduce_key="id")

      chunk_size = 100
      id_chunks = [
          id_list[x: x + chunk_size] for x in range(0, len(id_list), chunk_size)
      ]

      raw_results = [consumer.sync(id_values=chunk, executor_type="spark", spark_context=sc) for chunk in id_chunks]
      results = [item for sublist in raw_results for item in sublist]

      if len(results) > 0:
          logger.info("msg=Starting dataframe load.")
          df = _schema_enforcement(identifier, results)
          s3_loader.load_df(
              df=df, s3_path=f"{filesystem_path}{table_name}", format_options=file_type
          )

          spark_metastore_loader.update_metastore(
              df=df,
              database_name=database_name,
              table_name=table_name,
              format_options=file_type,
              database_location=filesystem_path,
              force_recreate=True,
          )

          spark_metastore_service.refresh_table(database_name, table_name)
