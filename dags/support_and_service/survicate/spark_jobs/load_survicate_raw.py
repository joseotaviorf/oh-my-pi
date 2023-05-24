import json
import logging
from argparse import ArgumentParser
from datetime import datetime

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
    SparkDataFrameService,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from quintoandar_logger import QuintoAndarLogger
from quintoandar_survicate_api_client.consumers import CONSUMERS
from bietlejuice.pipeline import IncrementalTableLoaderPipeline
from quintoandar_survicate_api_client.clients import SurvicateClient


JOB_NAME = "load_survicate_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

SCHEMA = """
    id STRING,
    custom_attributes STRUCT<
        ticket_id: STRING
    >,
    first_seen_date STRING,
    first_response_date STRING,
    answers ARRAY<
        STRUCT<
            survey_point: STRUCT<
                id: STRING,
                type: STRING,
                pretty_type: STRING,
                answer_type: STRING
            >,
            question: STRING,
            content: STRING
        >
    >,
    page_url STRING,
    visitor_id STRING,
    visitor_uuid STRING,
    response_uuid STRING
"""

def _parse_arguments():
    """
    This method aims to get the arguments passed from the dag.
    """
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("execution_date")
    parser.add_argument("tables_config")
    parser.add_argument("partition_cols")

    return parser.parse_args()


def get_api_token():
    """
    This method is intended to return the api connection settings.
    """
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        global dbutils
        dbutils = base_dbutils.get_dbutils()

    api_token_object = json.loads(
        dbutils.secrets.get(scope="quintoandar", key=APIEnum.SURVICATE)
    )
    
    return api_token_object["api_token"]

def _load_dataframe_into_datalake(args, force_recreate=True):
    """
    This method takes the data from the table in the Survicate API, considering the
    parameters if it is incremental or full load. In addition to also loading this data into the datalake.
    @param args: Detailing parameters of the tables..
    @param force_recreate: bool. Indicates if it must force table recreation in metastore.
    """
    tables_config = json.loads(args.tables_config)
    partition_cols = json.loads(args.partition_cols)
    dt_execution = datetime.strptime(args.execution_date, "%Y-%m-%d")

    api_token = get_api_token()
    spark_client = SparkClient()

    format_options = SparkTableStorageFormat.DEFAULT_RAW

    db_info = DatalakeMetastoreService.get_db_info(
        args.environment, args.source, args.datalake_bucket
    )
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]

    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)

    survicate_client = SurvicateClient(api_token=api_token)
    survey_list_consumer = CONSUMERS["survey_list"](survicate_client)
    survey_response_consumer = CONSUMERS["survey_response"](survicate_client)

    for table_name, infos in tables_config.items():
        survey_ids = survey_list_consumer.sync(flattened_key=infos["flattened_key"])
        results = survey_response_consumer.sync(args.execution_date, survey_ids)

        if results:
            df = spark_client.create_dataframe(results, schema=SCHEMA)

            df = (
                SparkDataFrameService()
                .input(df)
                .create_year_month_day_columns_from_date(dt_execution)
                .output()
            )

            IncrementalTableLoaderPipeline(
                database_name=database_name, 
                table_name=table_name, 
                database_location=database_location, 
                layer=LayerEnum.RAW,
                query=None,
                partitions=partition_cols
            ).load_and_register(df, format_options, force_recreate)

if __name__ == "__main__":
    args = _parse_arguments()

    logger.info(
        f"""
        m={JOB_NAME}, 
        environment={args.environment}, source={args.source}, dag_execution_date={args.execution_date}, 
        datalake_bucket={args.datalake_bucket}, tables_config={args.tables_config}, partition_cols={args.partition_cols}
        msg=Spark job arguments
        """
    )

    _load_dataframe_into_datalake(args)
