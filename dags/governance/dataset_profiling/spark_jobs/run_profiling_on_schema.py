from __future__ import annotations

from typing import Union
import json
import logging
from datetime import datetime

from argparse import ArgumentParser
from pyspark.sql.utils import AnalysisException

from inmetro.clients import (
    SparkClient as InmetroSparkClient,
    S3Client as InmetroS3Client,
)

from inmetro.loaders import S3Loader as InmetroS3Loader
from inmetro.parsers.profiles import PyDeequProfileParser
from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.base.service.service_enum import ServiceEnum
from bietlejuice.base.pipeline import MetadataTypeEnum
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.metadata_propagator_pipeline.dataset_profiling_pipeline import (
    DatasetProfilingPipeline,
)
from bietlejuice.base.udfs.udf_enum import UDFEnum

from bietlejuice.base.notification.slack_webhooks_enum import SlackWebhooksEnum
from bietlejuice.services.messaging_services.slack_service import SlackService


JOB_NAME = "dataset_profiling"
EXTRACTION_QUERY = r"""
SELECT distinct
  split(t.table,'\\\.')[1] as table,
  split(t.table,'\\\.')[0] as database_name, 
  t.dag,
  t.layer,
  d.dag_location
FROM
  datalake_dag_inventory_clean.table AS t
JOIN  datalake_dag_inventory_clean.dag AS d ON d.dag = t.dag AND d.dag = t.dag
WHERE
  d.day == {day} AND d.month == {month} AND d.year == {year}
  AND table like '{schema}.%'
  AND GET_PROFILING_DATA_QUALITY(replace(t.dag, 'bietlejuice.',''), t.layer, split(t.table,'\\\.')[1]) = "true"
"""

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def parse_args():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="Environment where the task is executing")
    parser.add_argument(
        "execution_date", type=str, help="Execution date when the task is executing"
    )
    parser.add_argument(
        "inmetro_bucket",
        type=str,
        help="Bucket that stores all the Inmetro's validation data",
    )
    parser.add_argument("schema", type=str, help="One of schemas on databricks")
    args = parser.parse_args()

    env = args.env
    execution_date_str = args.execution_date
    inmetro_bucket = args.inmetro_bucket.replace("s3://", "")
    schema = args.schema

    execution_date = datetime.strptime(execution_date_str, "%Y-%m-%d")

    return (env, execution_date, inmetro_bucket, schema)


def get_tables_from_schema(
    spark_client: SparkClient, query: str, query_params: dict[str : Union(str, int)]
) -> list[dict[str:str]]:

    """"
    This function takes the query so defined as variable and its parameters and checks the data quality files to return only the valid tables.
    
    :param spark_client: folder name in which is the queries and specifics spark jobs
    :type spark_client: str
    :param query: query to get table list from dag_inventory
    :type query: str
    :param query_params: parameters dictionary referenced on the query arg
    :type query_params: dict
    """

    formatted_query = query.format(**query_params)
    spark_client.conn.udf.register(
        "GET_PROFILING_DATA_QUALITY", UDFEnum.get_udf("GET_PROFILING_DATA_QUALITY")
    )

    df = spark_client.get_records(formatted_query)
    rows = df.rdd.map(lambda row: row.asDict()).collect()

    return [
        {
            "table_name": row["table"],
            "layer": row["layer"],
            "database_name": row["database_name"],
        }
        for row in rows
    ]


def send_result_to_inmetro_s3(
    inmetro_bucket: str, database_name: str, table_name: str, result: dict[str]
) -> None:

    """"
    This function gets the result json and sends to the correct inmetro bucket
    
    :param inmetro_bucket: inmetro bucket address
    :type inmetro_bucket: str
    :param database_name: schema name, such as metri_rent, dw_credit, etc
    :type database_name: str
    :param table_name: table name without schema
    :type table_name: str
    :param result: profiling result json woth dataset_size and columns statistics
    :type result: dict
    """

    s3_client = InmetroS3Client()
    s3_loader = InmetroS3Loader(bucket=inmetro_bucket, file_name=f"{table_name}.json")
    destination_directory = f"bietlejuice/{database_name}/{table_name}/profiling"
    s3_loader.upload(
        client=s3_client, output_parser=result, path_name=destination_directory
    )


if __name__ == "__main__":
    (env, execution_date, inmetro_bucket, schema) = parse_args()

    logger.info(
        f"m={JOB_NAME}, env={env}, inmetro_bucket={inmetro_bucket}, schema={schema}, "
        f"msg=Job execution started."
    )

    base_dbutils = BaseDBUtils()

    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    if env == "prod":
        key = SlackWebhooksEnum.ALERTS_AIRFLOW_DE_DAGS_INMETRO
    else:
        key = SlackWebhooksEnum.DE_TESTS

    slack_webhook = dbutils.secrets.get(scope="quintoandar", key=key)

    spark_client = SparkClient()

    query_params = {
        "day": execution_date.day,
        "month": execution_date.month,
        "year": execution_date.year,
        "schema": schema,
    }

    table_list = get_tables_from_schema(
        spark_client=spark_client, query=EXTRACTION_QUERY, query_params=query_params
    )
    logger.info(
        "m={}, msg=Got table list from schema {}, {} tables.".format(
            JOB_NAME, schema, len(table_list)
        )
    )

    inmetro_spark_client = InmetroSparkClient()

    for table in table_list:

        database_name, table_name = table["database_name"], table["table_name"]
        try:
            input_df = inmetro_spark_client.read_table(
                database_name=database_name, table_name=table_name
            )
        except AnalysisException as analysis_error:
            logger.error(
                f"m={JOB_NAME}, msg=Got a problem retriving table {database_name}.{table_name}! "
                f"Error_mesg={analysis_error}"
            )
            break

        if input_df.rdd.isEmpty():
            message = (
                f":warning:\n"
                f"Dataset profiling:\n"
                f"`{database_name}.{table_name}`\n"
                f"Status: `ERROR`\n\n"
                f"*The dataframe is empty*."
            )
            SlackService.send_slack_errors([(message, slack_webhook)])
            continue

        profiling_result = PyDeequProfileParser().run(input_df)
        profiling_result["dataset_size"] = input_df.count()

        logger.info(
            f"m={JOB_NAME}, msg=Ran profiling on table {database_name}.{table_name}."
        )

        send_result_to_inmetro_s3(
            inmetro_bucket=inmetro_bucket,
            database_name=database_name,
            table_name=table_name,
            result=profiling_result,
        )

        metadata_propagator_credentials = json.loads(
            dbutils.secrets.get(
                scope="quintoandar", key=ServiceEnum.METADATA_PROPAGATOR.value
            )
        )

        metadata_pipeline = DatasetProfilingPipeline(
            metadata_propagator_host=metadata_propagator_credentials["host"],
            database_name=database_name,
            table_name=table_name,
            metadata_type=MetadataTypeEnum.DATA_PROFILING,
            execution_date=execution_date.date(),
            profiling_dataset=profiling_result,
        )
        metadata_pipeline.run()

        logger.info(
            "m={}, msg=Dataset profiling executed for table {} with {} status.".format(
                JOB_NAME, table_name, metadata_pipeline.quality_check_status
            )
        )
