import ast
import json
import logging
import pyspark.sql.functions as F

from argparse import ArgumentParser
from datetime import datetime
from pyspark.sql.types import StructType, StructField, ArrayType

from quintoandar_logger import QuintoAndarLogger
from quintoandar_hubspot_api_client.consumers.hubspot_conversations_consumer import HubspotConversationsConsumer
from quintoandar_hubspot_api_client.clients.hubspot_client import HubspotClient
from quintoandar_hubspot_api_client.constants.endpoint_enum import EndpointEnum

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    BaseDBUtils,
    BaseSparkContext,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.formatters import StringFormatter

JOB_NAME = "load_hubspot_conversation_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

def _normalize_schema(schema: StructType) -> StructType:
    """
    Normalizes recursively the names of the fields in a Spark schema.
    """
    fields = []
    for field in schema.fields:
        name = StringFormatter.set_alphanumeric_snake_case(field.name)
        dtype = field.dataType
        if isinstance(dtype, StructType):
            dtype = _normalize_schema(dtype)
        elif isinstance(dtype, ArrayType) and isinstance(dtype.elementType, StructType):
            dtype = ArrayType(_normalize_schema(dtype.elementType))
        fields.append(StructField(name, dtype, field.nullable))
    return StructType(fields)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the API")
    parser.add_argument("custom_schema", help="name of the custom schema")
    parser.add_argument("data_interval_start", help="timestamp in str format %Y-%m-%d %H:%M:%S")
    parser.add_argument("data_interval_end", help="timestamp in str format %Y-%m-%d %H:%M:%S")
    parser.add_argument("table_name", help="Name of the table to store data into")
    parser.add_argument("partitions", help="Partition columns name")
    parser.add_argument("request_config", help="Request config")
    parser.add_argument("endpoint_params", help="Endpoint params")

    args = parser.parse_args()
    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    custom_schema = args.custom_schema
    data_interval_start = args.data_interval_start
    data_interval_end = args.data_interval_end
    table_name = args.table_name
    partitions = ast.literal_eval(args.partitions)
    request_config = json.loads(args.request_config)
    endpoint_params = json.loads(args.endpoint_params)

    logger.info(
        f"""
            m={JOB_NAME}, environment={args.environment}, source={args.source}, 
            data_interval_start={args.data_interval_start}, custom_schema={args.custom_schema},
            data_interval_end={args.data_interval_end}, datalake_bucket={args.datalake_bucket}, partition_cols={args.partitions}, 
            table_name={args.table_name}, request_config={args.request_config}, endpoint_params={args.endpoint_params}, 
            msg=print spark jobs args and variables"
        """
    )

    is_interval_data_filtered = request_config.get("is_interval_data_filtered", False)
    executor_type = request_config.get("executor_type", None)
    feedback_config = request_config.get("feedback_config", None)

    ts_interval_start = datetime.fromisoformat(data_interval_start)

    if is_interval_data_filtered:
        endpoint_params["interval_start_timestamp"] = data_interval_start
        endpoint_params["interval_end_timestamp"] = data_interval_end

    if feedback_config:
        feedback_config = json.loads(feedback_config)

        table = feedback_config.get("table")
        selected_column = feedback_config.get("selected_column")
        feedback_key = feedback_config.get("feedback_key")
        date_column_filter = feedback_config.get("date_column_filter")
        is_only_thread_executor_param = feedback_config.get("is_only_thread_executor_param", False)

        rows = (
            BaseSparkContext.spark.table(table)
            .filter(
                f"""
                DATE({date_column_filter}) BETWEEN DATE("{data_interval_start}") AND DATE("{data_interval_end}")
            """
            )
            .select(selected_column)
            .distinct()
            .collect()
        )
        feedback_parameters = [{f"{feedback_key}": row[selected_column]} for row in rows]

        if not feedback_parameters or feedback_parameters == []:
            logger.warning(
                f"""
                    m={JOB_NAME}, feedback_config={feedback_config}, seleted_table={table}, 
                    selected_column={selected_column}, feedback_key={feedback_key}, 
                    date_column_filter={date_column_filter}, table_name={table_name}, 
                    msg=feedback_parameters is empty"
                """
            )
    else:
        feedback_parameters = None
        is_only_thread_executor_param = None

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    api_token = json.loads(
        dbutils.secrets.get(scope="quintoandar", key=APIEnum.HUBSPOT)
    )['token']

    hubspot_client = HubspotClient(api_token)
    endpoint_enum = EndpointEnum[table_name.upper()].value
    consumer = HubspotConversationsConsumer(client=hubspot_client, endpoint_enum=endpoint_enum)

    logger.info(
        f"""
            m={JOB_NAME}, table_name={table_name}, params={endpoint_params}, 
            feedback_parameters={feedback_parameters},
            executor_type={executor_type}, endpoint_enum={endpoint_enum},
            ts_interval_start={ts_interval_start},
            is_only_thread_executor_param={is_only_thread_executor_param},
            msg=starting sync request to hubspot api..."
        """
    )

    response = consumer.sync(
        params=endpoint_params,
        thread_executor_params=feedback_parameters if is_only_thread_executor_param == True else None,
        feedback_list=feedback_parameters if is_only_thread_executor_param == False else None,
        executor_type=executor_type,
    )

    if response:
        spark_client = SparkClient()
        json_lines = [json.dumps(item) for item in response]
        response_rdd = spark_client.conn.sparkContext.parallelize(json_lines)
        df = spark.read.json(response_rdd)

        new_schema = _normalize_schema(df.schema)
        df = spark_client.create_dataframe(df.rdd, schema=new_schema)

        df = (
            df.withColumn("ts_load", F.lit(ts_interval_start))
            .withColumn("year", F.lit(ts_interval_start.year))
            .withColumn("month", F.lit(ts_interval_start.month))
            .withColumn("day", F.lit(ts_interval_start.day))
            .withColumn("hour", F.lit(ts_interval_start.hour))
        )

        db_info = DatalakeMetastoreService.get_db_info(
            environment, custom_schema, datalake_bucket
        )
        database_name = db_info["db_raw_databricks"]
        database_location = db_info["db_raw_path"]

        loader = DeltaLoader()
        loader.load_table(
            table_name=f"{database_name}.{table_name}",
            path=f"{database_location}{table_name}",
            source_df=df,
            partition_by=partitions,
        )

    else:
        logger.warning(
            f"""
                m={JOB_NAME}, table_name={table_name}, params={endpoint_params}, 
                feedback_parameters={feedback_parameters}, request_config={request_config},
                executor_type={executor_type}, endpoint_enum={endpoint_enum},
                data_interval_start={data_interval_start}, data_interval_end={data_interval_end},
                ts_interval_start={ts_interval_start}, feedback_config={feedback_config},
                is_only_thread_executor_param={is_only_thread_executor_param},
                feedback_list={feedback_parameters if is_only_thread_executor_param == False else None},
                thread_executor_params={feedback_parameters if is_only_thread_executor_param == True else None},
                msg=api response is empty"
            """
        )