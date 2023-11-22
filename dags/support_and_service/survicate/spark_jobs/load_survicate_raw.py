import json
import logging
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
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
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


def _parse_arguments():
    """
    This method aims to get the arguments passed from the dag.
    """
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("tables_config")
    parser.add_argument("raw_table_name")
    parser.add_argument("partition_cols")
    parser.add_argument("execution_date")

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
        dbutils.secrets.get(scope=SCOPE, key=APIEnum.SURVICATE)
    )

    return api_token_object["api_token"]


def _load_dataframe_into_datalake(args, force_recreate=True):
    """
    This method takes the data from the table in the Survicate API, considering the
    parameters if it is incremental or full load. In addition to also loading this data into the datalake.
    @param args: Detailing parameters of the tables..
    @param force_recreate: bool. Indicates if it must force table recreation in metastore.
    """
    raw_table_name = args.raw_table_name
    partition_cols = json.loads(args.partition_cols)

    execution_date = args.execution_date
    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")

    tables_config = json.loads(args.tables_config)
    endpoint_enum = tables_config.get("endpoint_enum")
    optional_parameters = tables_config.get("optional_parameters")
    feedback_parameters = tables_config.get("feedback_parameters_query")

    if optional_parameters.get("start"):
        optional_parameters["start"] = optional_parameters.get("start").format(
            execution_date=execution_date
        )
    if optional_parameters.get("end"):
        optional_parameters["end"] = optional_parameters.get("end").format(
            execution_date=execution_date
        )
    if feedback_parameters:
        feedback_parameters = feedback_parameters.format(execution_date=execution_date)
        df = spark.sql(feedback_parameters)

        feedback_parameters = list(map(lambda row: row.asDict(), df.collect()))

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
    survicate_consumer = SurvicateConsumer(survicate_client)

    if feedback_parameters != []:
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

            IncrementalTableLoaderPipeline(
                database_name=database_name,
                table_name=raw_table_name,
                database_location=database_location,
                layer=LayerEnum.RAW,
                query=None,
                partitions=partition_cols,
            ).load_and_register(df, format_options, force_recreate)

        else:
            logger.warning(
                f"""
                m={JOB_NAME},
                environment=dag_execution_date={args.execution_date}, raw_table_name={args.raw_table_name}
                msg=The API request returned no data, so no data was loaded for the current execution date.
                """
            )
    else:
        logger.warning(
            f"""
            m={JOB_NAME},
            environment=dag_execution_date={args.execution_date}, raw_table_name={args.raw_table_name}
            msg=No data to feed back to the API, so no data was loaded for the current execution date.
            """
        )

    if __name__ == "__main__":
        args = _parse_arguments()

        logger.info(
            f"""
            m={JOB_NAME},
            environment={args.environment}, source={args.source}, execution_date={args.execution_date}, table_name={args.raw_table_name},
            datalake_bucket={args.datalake_bucket}, tables_config={args.tables_config}, partition_cols={args.partition_cols}
            msg=Spark job arguments
            """
        )

        _load_dataframe_into_datalake(args)
