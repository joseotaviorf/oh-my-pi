import ast
import json
import logging
from argparse import ArgumentParser
from datetime import datetime

import pyspark.sql.functions as F
from quintoandar_jira_api_client.clients import JiraClient
from quintoandar_jira_api_client.consumers import CONSUMERS
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, BaseSparkContext
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_jira_ops_data_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="")
    parser.add_argument("load_start_date", help="start execution date in str format")
    parser.add_argument("load_end_date", help="end execution date in str format")
    parser.add_argument("partitions", help="")
    parser.add_argument("table_name", help="")
    parser.add_argument("endpoint_params", help="")

    add_validation_target_args(parser)
    args = parser.parse_args()
    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    partition_cols = ast.literal_eval(args.partitions)

    load_start_date = args.load_start_date
    load_end_date = args.load_end_date

    dt_start_execution = datetime.strptime(load_start_date, "%Y-%m-%d").date()
    dt_end_execution = datetime.strptime(load_end_date, "%Y-%m-%d").date()

    endpoint_params = json.loads(args.endpoint_params)
    endpoint_enum = endpoint_params.get("endpoint_enum")
    jql_query_filter = endpoint_params.get("jql_query_filter")
    feedback_config = json.loads(endpoint_params.get("feedback_config", "{}"))
    params = json.loads(endpoint_params.get("params", "{}"))
    api_enum = endpoint_params.get("api_enum")
    consumer = endpoint_params.get("consumer", "jira_ops")

    logger.info(
        f"""
            m={JOB_NAME}, environment={args.environment}, source={args.source}, load_start_date={args.load_start_date},
            load_end_date={args.load_end_date}, datalake_bucket={args.datalake_bucket}, partition_cols={args.partitions}, 
            table_name={args.table_name}, endpoint_params={args.endpoint_params}, msg=print spark jobs args"
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    if api_enum:
        api_enum_value = getattr(APIEnum, api_enum)
    else:
        api_enum_value = APIEnum.JIRA_OPS

    json_credentials = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key=api_enum_value)
    credentials = json.loads(json_credentials)

    if credentials.get("cloud_id") and params.get("cloud_id"):
        params["cloud_id"] = credentials.get("cloud_id")

    jira_client = JiraClient(
        username=credentials["username"],
        token=credentials["token"],
        server=credentials["server"],
    )

    jira_consumer = CONSUMERS[consumer](jira_client)

    response = None

    if jql_query_filter:
        startTime = int(
            datetime.combine(dt_start_execution, datetime.min.time()).timestamp()
        )
        endTime = int(
            datetime.combine(dt_end_execution, datetime.max.time()).timestamp()
        )

        jql_query_filter = (
            jql_query_filter + f" AND createdAt > {startTime} AND createdAt < {endTime}"
        )
        params["query"] = jql_query_filter

    if feedback_config:
        table = feedback_config.get("table")
        seleted_column = feedback_config.get("seleted_column")
        feedback_key = feedback_config.get("feedback_key")
        date_column_filter = feedback_config.get("date_column_filter")

        rows = (
            BaseSparkContext.spark.table(table)
            .filter(
                f"""
                    DATE({date_column_filter}) BETWEEN DATE("{load_start_date}") AND DATE("{load_end_date}")
                    AND {seleted_column} IS NOT NULL
                """
            )
            .select(seleted_column)
            .collect()
        )
        feedback_parameters = [{f"{feedback_key}": row[seleted_column]} for row in rows]

        if feedback_parameters and feedback_parameters != []:
            response = jira_consumer.sync(
                endpoint_enum=endpoint_enum,
                feedback_parameters=feedback_parameters,
                params=params,
            )
        else:
            logger.warn(
                f"""
                    m={JOB_NAME}, feedback_config={feedback_config}, seleted_table={table}, 
                    seleted_column={seleted_column}, feedback_key={feedback_key}, 
                    date_column_filter={date_column_filter}, table_name={table_name}, 
                    msg=feedback_parameters is empty"
                """
            )

    else:
        response = jira_consumer.sync(endpoint_enum=endpoint_enum, params=params)

    if response:
        spark_client = SparkClient()

        json_lines = [json.dumps(item) for item in response]
        response_rdd = spark_client.conn.sparkContext.parallelize(json_lines)

        df = spark.read.json(response_rdd)

        df = (
            df.withColumn("dt_load", F.lit(dt_end_execution))
            .withColumn("year", F.lit(dt_end_execution.year))
            .withColumn("month", F.lit(dt_end_execution.month))
            .withColumn("day", F.lit(dt_end_execution.day))
        )

        db_info = DatalakeMetastoreService.get_db_info(
            environment, source, datalake_bucket
        )
        database_name = db_info["db_raw_databricks"]
        database_location = db_info["db_raw_path"]
        write_database_name, write_table_name, write_location = (
            resolve_datalake_write_target(
                prod_database=database_name,
                prod_table=table_name,
                prod_location=database_location,
                bucket=datalake_bucket,
                target_database=args.target_database_name,
                target_table=args.target_table_name,
            )
        )

        loader = DeltaLoader()
        loader.load_table(
            table_name=f"{write_database_name}.{write_table_name}",
            path=f"{write_location}{write_table_name}",
            source_df=df,
            partition_by=partition_cols,
        )

    else:
        logger.warn(
            f"""
            m={JOB_NAME}, endpoint_enum={endpoint_enum}, params={params}, 
            feedback_config={feedback_config}, table_name={table_name}, 
            msg=api response is empty"
        """
        )
