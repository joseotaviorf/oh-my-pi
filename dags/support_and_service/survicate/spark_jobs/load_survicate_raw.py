import json
import logging
from argparse import ArgumentParser
from bs4 import BeautifulSoup
from datetime import datetime
from pyspark.sql.functions import lit, col

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
    SparkDataFrameService,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.pipeline import IncrementalTableLoaderPipeline

from quintoandar_logger import QuintoAndarLogger
from quintoandar_survicate_api_client.clients import SurvicateClient
from quintoandar_survicate_api_client.consumers.survicate_consumer import (
    SurvicateConsumer,
)


JOB_NAME = "load_survicate_raw"
SCOPE = "quintoandar"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

def workspace_mapping_key(workspace_list: list) -> dict:
    """
    Creates a mapping dict to get API Key for each Workspace
    """
    api_key_mapping = {}
    for workspace in workspace_list:
        if workspace == "Production":
            api_key_mapping[workspace] = APIEnum.SURVICATE
        elif workspace == "P&T | Prod":
            api_key_mapping[workspace] = APIEnum.SURVICATE_PET
        else: 
            logger.error('Could not retrieve API Key for workspace: {}'.format(workspace))

    return api_key_mapping

def get_api_token(workspace_api_token):
    """
    This method is intended to return the api connection settings.
    """
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        global dbutils
        dbutils = base_dbutils.get_dbutils()

    api_token_object = json.loads(
        dbutils.secrets.get(scope=SCOPE, key=workspace_api_token)
    )

    return api_token_object["api_token"]


def _load_dataframe_into_datalake(args, force_recreate=True):
    """
    This method takes the data from the table in the Survicate API, for each workspace, considering the
    parameters if it is incremental or full load. In addition to also loading this data into the datalake.
    @param args: Detailing parameters of the tables..
    @param force_recreate: bool. Indicates if it must force table recreation in metastore.
    """

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    raw_table_name = args.raw_table_name
    execution_date = args.execution_date
    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")

    config_service = ConfigurationService(source)
    partition_cols = config_service.get_config("partition_cols")
    tables = config_service.get_config("tables")
    workspace_list = config_service.get_config("workspaces")

    table_config = tables.get(raw_table_name)

    endpoint_enum = table_config.get("endpoint_enum")
    optional_parameters = table_config.get("optional_parameters")
    feedback_parameters_query = table_config.get("feedback_parameters_query")

    logger.info("m=__main__, msg=Format start date...")
    optional_parameters["start"] = optional_parameters.get("start").format(
        execution_date=execution_date
    )

    if optional_parameters.get("end"):
        logger.info("m=__main__, msg=Format end date...")
        optional_parameters["end"] = optional_parameters.get("end").format(
            execution_date=execution_date
        )

    feedback_parameters = None
    if feedback_parameters_query:
        logger.info("m=__main__, msg=This table has feedback parameters...")
        logger.info("m=__main__, msg=Format feedback parameters...")
        feedback_parameters_query = feedback_parameters_query.format(
            execution_date=execution_date
        )

        df = spark.sql(feedback_parameters_query)

        feedback_parameters = list(map(lambda row: row.asDict(), df.collect()))
    
    unioned_df = None
    api_key_mapping = workspace_mapping_key(workspace_list)
    for workspace in api_key_mapping:
        workspace_api_token = api_key_mapping[workspace]
        api_token = get_api_token(workspace_api_token)
        spark_client = SparkClient()

        format_options = SparkTableStorageFormat.DEFAULT_RAW

        db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
        database_name = db_info["db_raw_databricks"]
        database_location = db_info["db_raw_path"]

        spark_metastore_service = SparkMetastoreService(spark_client)

        logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
        spark_metastore_service.create_database(database_name)

        survicate_client = SurvicateClient(api_token=api_token)
        survicate_consumer = SurvicateConsumer(survicate_client)

        if not feedback_parameters_query or feedback_parameters != []:
            response = survicate_consumer.sync(
                endpoint_enum=endpoint_enum,
                feedback_parameters=feedback_parameters,
                params=optional_parameters,
            )

            if response:
                for row in response:
                    for name, raw_text_html in row.items():
                        clean_text = BeautifulSoup(
                            str(raw_text_html), "html.parser"
                        ).get_text(strip=True)
                        row[name] = str(clean_text)

                rdd_response = spark_client.conn.sparkContext.parallelize(response)
                df = spark.read.json(rdd_response, multiLine=True)

                df = df.withColumn("dt_load", lit(dt_execution))
                df = (
                    SparkDataFrameService()
                    .input(df)
                    .create_year_month_day_columns_from_date(dt_execution)
                    .output()
                )
                if not unioned_df:
                    unioned_df = df
                else:
                    unioned_df = unioned_df.union(df)

                IncrementalTableLoaderPipeline(
                    database_name=database_name,
                    table_name=raw_table_name,
                    database_location=database_location,
                    layer=LayerEnum.RAW,
                    query=None,
                    partitions=partition_cols,
                ).load_and_register(unioned_df, format_options, force_recreate)

            else:
                logger.warning(
                    f"""
                    m={JOB_NAME},
                    environment=dag_execution_date={args.execution_date}, raw_table_name={raw_table_name}
                    msg=The API request returned no data, so no data was loaded for the current execution date.
                    """
                )
        
        else:
            logger.warning(
                f"""
                m={JOB_NAME},
                environment={environment}, dag_execution_date={args.execution_date}, raw_table_name={raw_table_name}
                msg=No data to feed back to the API, so no data was loaded for the current execution date.
                """
            )


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("raw_table_name")
    parser.add_argument("execution_date")

    args = parser.parse_args()

    logger.info(
        f"""
        m={JOB_NAME},
        environment={args.environment}, source={args.source}, execution_date={args.execution_date},
        datalake_bucket={args.datalake_bucket}, table_name={args.raw_table_name}
        msg=Spark job arguments
        """
    )

    _load_dataframe_into_datalake(args)
