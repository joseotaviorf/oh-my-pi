import json
import logging
import time
from argparse import ArgumentParser
from bs4 import BeautifulSoup
from datetime import datetime
from pyspark.sql.functions import lit

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
    SparkDataFrameService,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.pipeline import IncrementalTableLoaderPipeline

from quintoandar_logger import QuintoAndarLogger
from quintoandar_survicate_api_client.clients import SurvicateClient
from quintoandar_survicate_api_client.consumers.survicate_consumer import (
    SurvicateConsumer,
)

job_name = "load_survicate_test__raw"
scope = "quintoandar"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(job_name)

def workspace_mapping_key(workspace_list: list) -> dict:
    """
    Creates a mapping dict to get API Key for each Workspace.
    @param workspace_list: list of workspace strings.
    @return: dict of workspace name as keys and api key as values.
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
        dbutils.secrets.get(scope=scope, key=workspace_api_token)
    )

    return api_token_object["api_token"]

def table_configs(table_name: str):
    """
    Method for defining, for each table_name, the values for endpoint_enum, feedback_parameters_query
    and optional_parameters.
    @param table name: table name as string
    @return endpoint_enum: endpoint as string
    @return feedback_parameters_query: string for datalake querying
    @return optional_parameters: API optional parameters

    """
    start = "{execution_date}T23:59:59.000000Z"
    end = "{execution_date}T00:00:00.000000Z"

    if table_name == 'surveys':
        endpoint_enum = 'SURVEYS'
        feedback_parameters_query = None
        optional_parameters = {"items_per_page": 100,
                               "start": start,
                               "end": end}
        
    elif table_name == 'survey_questions':
        endpoint_enum = 'SURVEY_QUESTIONS'
        feedback_parameters_query = "SELECT DISTINCT id AS survey_id FROM datalake_survicate_test_raw.surveys WHERE workspace_name = '{workspace}'"
        optional_parameters = {"items_per_page": 100,
                               "start": start,
                               "end": end}
  
    elif table_name == 'survey_responses':
        endpoint_enum = 'SURVEY_RESPONSES'
        feedback_parameters_query = "SELECT DISTINCT id AS survey_id FROM datalake_survicate_test_raw.surveys WHERE workspace_name = '{workspace}'"
        optional_parameters = {"items_per_page": 100,
                               "start": start,
                               "end": end}
    
    elif table_name == "respondent_attributes":
        endpoint_enum = 'RESPONDENT_ATTRIBUTES'
        feedback_parameters_query = "SELECT DISTINCT GET_JSON_OBJECT(respondent, '$.uuid') AS respondent_uuid FROM datalake_survicate_test_raw.survey_responses WHERE DATE(dt_load) = DATE('{execution_date}') and workspace_name = '{workspace}'"
        optional_parameters = {"items_per_page": 100,
                               "start": start} 
           
    return endpoint_enum, feedback_parameters_query, optional_parameters

def _load_dataframe_into_datalake(args, force_recreate=True):
    """
    This method takes the data from the table in the Survicate API, for each workspace, considering the
    parameters if it is incremental or full load. In addition to also loading this data into the datalake.
    @param args: Detailing parameters of the tables..
    @param force_recreate: bool. Indicates if it must force table recreation in metastore.
    """

    environment = args.environment
    bucket = args.bucket
    execution_date = args.execution_date
    dag_name = args.dag_name
    table_name = args.table_name

    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
    
    partitions = ["year", "month", "day"]
    workspace_list = ["Production", "P&T | Prod"]

    unioned_df = None
    api_key_mapping = workspace_mapping_key(workspace_list)
    for workspace in api_key_mapping:
        workspace_api_token = api_key_mapping[workspace]

        endpoint_enum, feedback_parameters_query, optional_parameters = table_configs(table_name)

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
                execution_date=execution_date,
                workspace = workspace
            )

            df = spark.sql(feedback_parameters_query)

            while df.rdd.isEmpty():
                logger.warning(f"m={job_name}, environment={environment}, dag_execution_date={args.execution_date}, table_name={table_name}, msg=DataFrame is empty for workspace {workspace}. Waiting 5 minutes.")
                time.sleep(300)
                df = spark.sql(feedback_parameters_query)

            feedback_parameters = list(map(lambda row: row.asDict(), df.collect()))

        api_token = get_api_token(workspace_api_token)
        spark_client = SparkClient()

        format_options = SparkTableStorageFormat.DEFAULT_RAW

        db_info = DatalakeMetastoreService.get_db_info(environment, dag_name, bucket)
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
                df = df.withColumn("workspace_name", lit(workspace))
                df = (
                    SparkDataFrameService()
                    .input(df)
                    .create_year_month_day_columns_from_date(dt_execution)
                    .output()
                )

                if unioned_df is None:
                    unioned_df = df
                else:
                    unioned_df = unioned_df.unionByName(df, allowMissingColumns=True)

            else:
                logger.warning(
                    f"""
                    m={job_name},
                    environment=dag_execution_date={args.execution_date}, table_name={table_name}
                    msg=The API request returned no data, so no data was loaded for the current execution date for workspace {workspace}.
                    """
                )
        else:
            logger.warning(
                f"""
                m={job_name},
                environment={environment}, dag_execution_date={args.execution_date}, table_name={table_name}
                msg=No data to feed back to the API, so no data was loaded for the current execution date.
                """
            )
    if unioned_df:
        IncrementalTableLoaderPipeline(
                database_name=database_name,
                table_name=table_name,
                database_location=database_location,
                layer=LayerEnum.RAW,
                query=None,
                partitions=partitions,
                ).load_and_register(unioned_df, format_options, force_recreate)
    else:
       logger.warning(
                f"""
                m={job_name},
                environment={environment}, dag_execution_date={args.execution_date}, table_name={table_name}
                msg=No data to feed back to the API, so no data was loaded for the current execution date.
                """
            )


if __name__ == "__main__":
    parser = ArgumentParser(description=job_name)
    parser.add_argument("environment")
    parser.add_argument("bucket")
    parser.add_argument("execution_date")
    parser.add_argument("dag_name")
    parser.add_argument("table_name")
    parser.add_argument("partitions")

    args = parser.parse_args()

    logger.info(
        f"""
        m={job_name},
        environment={args.environment}, dag_name={args.dag_name}, execution_date={args.execution_date},
        bucket={args.bucket}, table_name={args.table_name}
        msg=Spark job arguments
        """
    )
    _load_dataframe_into_datalake(args)