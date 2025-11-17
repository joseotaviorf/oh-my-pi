import ast
import json
import logging
import random
import requests
import time

from argparse import ArgumentParser
from datetime import datetime
from pyspark.sql import functions as F
from pyspark.sql import Row
from pyspark.sql.types import (
    StructType,
    StructField,
    StringType,
    ArrayType,
    LongType,
)

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    BaseDBUtils,
    BaseSparkContext,
)
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.metastore_services import SparkMetastoreService

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "conversation_sentiment_analysis"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

def _get_thread_conversation_rows(
    table_name_base, 
    date_column_filter, 
    selected_columns, 
    data_interval_start, 
    data_interval_end
):

    df = (
        BaseSparkContext.spark.table(table_name_base)
            .filter(
                F.col(date_column_filter).cast("date").between(
                    F.to_date(F.lit(data_interval_start)),
                    F.to_date(F.lit(data_interval_end))
                )
            )
        .select(*selected_columns)
        .distinct()
    )

    if df.rdd.isEmpty():
        return None

    df_fmt = (
        df
        .filter(F.col("message_text").isNotNull())
        .withColumn("message", F.concat(F.lit("["), F.col("sender_type"), F.lit("]: "), F.col("message_text")))
    )

    df_struct = (
        df_fmt
        .groupBy(["id_inbox", "id_thread", "id_associated_contact"])
        .agg(
            F.collect_list(
                F.struct(
                    F.col("ts_message_created").alias("ts_message_created"),
                    F.col("message").alias("message")
                )
            ).alias("msg_structs")
        )
    )

    df_sorted = df_struct.withColumn(
        "msg_structs_sorted",
        F.array_sort(F.col("msg_structs"))
    )

    df_final = (
        df_sorted
        .withColumn("messages", F.expr("transform(msg_structs_sorted, x -> x.message)"))
        .withColumn("timestamps", F.expr("transform(msg_structs_sorted, x -> cast(x.ts_message_created as string))"))
        .withColumn("message_history", F.concat_ws("\n", F.col("messages")))
        .withColumn("ts_message_history", F.concat_ws("\n", F.col("timestamps")))
        .select("id_inbox", "id_thread", "id_associated_contact", "message_history", "ts_message_history")
    )

    return df_final

def _evaluate_conversation(
    session: requests.Session,
    url, 
    model, 
    prompt, 
    headers, 
    text, 
    max_len=3000, 
    retries=3
):
    """
    Calls the Claude API to evaluate a conversation.
    Returns both the cleaned text output and the raw JSON response.
    """
    text = text[-max_len:]
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": prompt},
            {"role": "user", "content": text}
        ]
    }

    for attempt in range(retries):
        try:
            r = session.post(url, headers=headers, json=payload, timeout=40)
            r.raise_for_status()
            raw_response = r.json()
            clean_text = raw_response.get("choices", [{}])[0].get("message", {}).get("content", "").strip()
            return clean_text, json.dumps(raw_response)
        except Exception as e:
            if attempt < retries - 1:
                wait_time = 2 ** attempt + random.random()
                time.sleep(wait_time)
            else:
                return f"Error: {e}", None

def _evaluate_conversation_in_batches(
    session: requests.Session,
    url, 
    model, 
    prompt, 
    headers, 
    full_text, 
    batch_size=20
):
    """
    Splits a long conversation into batches and evaluates each batch separately.
    """
    messages = full_text.split("\n")
    text_results, raw_results = [], []

    for i in range(0, len(messages), batch_size):
        batch = "\n".join(messages[i:i+batch_size])
        text_out, raw_out = _evaluate_conversation(session, url, model, prompt, headers, batch)
        text_results.append(text_out)
        raw_results.append(raw_out)

    return text_results, raw_results

def _process_partition(
    url, 
    model, 
    prompt, 
    headers, 
    iterator
):
    log = logging.getLogger(JOB_NAME)

    session = requests.Session()
    try:
        for row in iterator:
            try:
                evaluated_list, raw_response_list = _evaluate_conversation_in_batches(session, url, model, prompt, headers, row.message_history)
                satisfactory_sentiment = [t for t in evaluated_list if "Sentimento: Satisfatório" in t]
                negative_sentiment = [t for t in evaluated_list if "Sentimento: Negativo" in t]

                new_row = row.asDict() | {
                    "detailed_sentiment": evaluated_list,
                    "satisfactory_sentiment": satisfactory_sentiment,
                    "negative_sentiment": negative_sentiment,
                    "raw_response": raw_response_list
                }
            except Exception as e:
                log.error(
                    f"""
                        m={JOB_NAME}, error={e},
                        msg=error evaluating conversation"
                    """
                )
                new_row = row.asDict() | {
                    "detailed_sentiment": [f"Error: {e}"],
                    "satisfactory_sentiment": [],
                    "negative_sentiment": [],
                    "raw_response": [],
                }

            yield Row(**new_row)

    finally:
        session.close()
    

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the API")
    parser.add_argument("custom_schema", help="name of the custom schema")
    parser.add_argument("table_name", help="Name of the table to store data into")
    parser.add_argument("data_interval_start", help="timestamp in str format %Y-%m-%d %H:%M:%S")
    parser.add_argument("data_interval_end", help="timestamp in str format %Y-%m-%d %H:%M:%S")
    parser.add_argument("partitions", help="Partition columns name")
    parser.add_argument("dataframe_base_config", help="DataFrame base configuration")
    parser.add_argument("claude_api_config", help="Claude API configuration")

    args = parser.parse_args()
    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    custom_schema = args.custom_schema
    table_name = args.table_name
    data_interval_start = args.data_interval_start
    data_interval_end = args.data_interval_end
    partitions = ast.literal_eval(args.partitions)
    dataframe_base_config = json.loads(args.dataframe_base_config)
    claude_api_config = json.loads(args.claude_api_config)

    logger.info(
        f"""
            m={JOB_NAME}, environment={args.environment}, source={args.source}, 
            data_interval_start={args.data_interval_start}, dataframe_base_config={args.dataframe_base_config},
            data_interval_end={args.data_interval_end}, datalake_bucket={args.datalake_bucket}, 
            table_name={args.table_name}, partition_cols={args.partitions}, 
            msg=print spark jobs args and variables"
        """
    )

    dt_interval_start = datetime.fromisoformat(data_interval_start)
    table_name_base = dataframe_base_config.get("table_name_base")
    date_column_filter = dataframe_base_config.get("date_column_filter")
    selected_columns = dataframe_base_config.get("selected_columns")

    logger.info(
        f"""
            m={JOB_NAME}, table_name_base={table_name_base}, date_column_filter={date_column_filter}, selected_columns={selected_columns}, 
            data_interval_start={data_interval_start}, data_interval_end={data_interval_end},
            msg=starting get thread conversation rows from {table_name_base} table..."
        """
    )

    df_base = _get_thread_conversation_rows(
        table_name_base,
        date_column_filter,
        selected_columns,
        data_interval_start,
        data_interval_end
    )

    if df_base is None:
        logger.warning(
            f"""
                m={JOB_NAME}, table_name_base={table_name_base}, date_column_filter={date_column_filter}, selected_columns={selected_columns}, 
                data_interval_start={data_interval_start}, data_interval_end={data_interval_end},
                msg=no rows found in the {table_name_base} table for the given date interval"
            """
        )
        exit(0)
        
    else:
        logger.info(
            f"""
                m={JOB_NAME}, table_name={table_name}, partitions={partitions}, custom_schema={custom_schema},
                data_interval_start={data_interval_start}, data_interval_end={data_interval_end},
                msg=starting conversation sentiment analysis..."
            """
        )

        base_dbutils = BaseDBUtils()
        if base_dbutils.get_dbutils() is not None:
            dbutils = base_dbutils.get_dbutils()

        claude_api_token = dbutils.secrets.get(scope="quintoandar", key=APIEnum.CLAUDE_SONNET_4)
        
        base_url = json.loads(claude_api_config.get("base_url")).get(environment)
        endpoint = claude_api_config.get("endpoint")
        headers = json.loads(claude_api_config.get("headers")).copy()

        headers["Authorization"] = f"{headers['Authorization']} {claude_api_token}"

        spark_client = SparkClient()
        sc = spark_client.conn.sparkContext
        bc_url = sc.broadcast(f"{base_url}/{endpoint}")
        bc_model = sc.broadcast(claude_api_config.get("model"))
        bc_prompt = sc.broadcast(claude_api_config.get("prompt"))
        bc_headers = sc.broadcast(headers)

        df_base = df_base.repartition(20).cache()

        logger.info(
            f"""
                m={JOB_NAME}, url={bc_url.value}, model={bc_model.value}, prompt={bc_prompt.value}
                msg=starting conversation sentiment analysis..."
            """
        )

        evaluate_partition = lambda iterator: _process_partition(
            bc_url.value, bc_model.value, bc_prompt.value, bc_headers.value, iterator
        )

        rdd_result = df_base.rdd.mapPartitions(evaluate_partition)

        df_schema = StructType([
            StructField("id_inbox", LongType(), True),
            StructField("id_thread", LongType(), True),
            StructField("id_associated_contact", LongType(), True),
            StructField("message_history", StringType(), True),
            StructField("ts_message_history", StringType(), True),
            StructField("detailed_sentiment", ArrayType(StringType(), True), True),
            StructField("satisfactory_sentiment", ArrayType(StringType(), True), True),
            StructField("negative_sentiment", ArrayType(StringType(), True), True),
            StructField("raw_response", ArrayType(StringType(), True), True),
        ])

        df_result = spark_client.create_dataframe(rdd_result, schema=df_schema)

        df_base.unpersist()

        logger.info(
            f"""
                m={JOB_NAME}, url={bc_url.value}, model={bc_model.value}, prompt={bc_prompt.value}
                msg=ended conversation sentiment analysis, starting to load data with delta loader..."
            """
        )

        df_result = (
            df_result.withColumn("ts_load", F.lit(dt_interval_start.date()))
            .withColumn("year", F.lit(dt_interval_start.year))
            .withColumn("month", F.lit(dt_interval_start.month))
            .withColumn("day", F.lit(dt_interval_start.day))
        )

        db_info = DatalakeMetastoreService.get_db_info(
            environment, custom_schema, datalake_bucket
        )
        database_name = db_info["db_enrich_databricks"]
        database_location = db_info["db_enrich_path"]

        loader = DeltaLoader()
        loader.load_table(
            table_name=f"{database_name}.{table_name}",
            path=f"{database_location}{table_name}",
            source_df=df_result,
            partition_by=partitions,
        )

        spark_metastore_service = SparkMetastoreService(spark_client)
        spark_metastore_service.refresh_table(
            database_name, table_name
        )

        table_privileges = TablePrivileges.from_environment_default(f"{database_name}.{table_name}")
        if (
            table_privileges
            and UnityCatalogHelper.is_cluster_unity_catalog_enabled()
        ):
            table_privileges.apply()

        logger.info(
            f"""
                m={JOB_NAME}, table_name={table_name}, data_interval_start={data_interval_start}, data_interval_end={data_interval_end},
                msg=conversation sentiment analysis completed successfully"
            """
        )