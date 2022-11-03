import json
import logging
import urllib3
from argparse import ArgumentParser
from datetime import datetime, timedelta

from quintoandar_sap_api_client.clients import SapClient
from quintoandar_sap_api_client.consumers import CONSUMERS
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    BaseDBUtils,
    BaseSparkContext,
    SparkDataFrameService,
    SparkTableStorageFormat,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.formatters import StringFormatter
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService

from pyspark.sql.types import StructType

JOB_NAME = "load_incremental_sap_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


def extend_incremental_params(params: dict, execution_date: str) -> dict:
    """Function to parse and add incremental param in the current params.

    :param params: Dict with request params
    :type params: dict
    :param execution_date: Execution_date as string
    :type execution_date: str
    :return: Dict of extended params
    :rtype: dict
    """

    from_day = datetime.strptime(execution_date, "%Y-%m-%d")
    to_day = (from_day + timedelta(days=1)).strftime("%Y-%m-%d")
    params["from_day"] = "'{0}'".format(execution_date)
    params["to_day"] = "'{0}'".format(to_day)

    return params


def parse_records(records: list, schema_content: str):
    """Function to parse and convert response records into a dataframe

    :param records: Raw records from consumer/API reponse
    :type records: list[dict]
    :param schema_content: Pyspark Schema in JSON form
    :type records: str
    :return: Dataframe with formatted columns
    :rtype: Spark Dataframe
    """

    response = BaseSparkContext.sc.parallelize(records)

    schema = StructType.fromJson(schema_content)

    df = spark_client.create_dataframe(response, schema)

    formatted_columns = list(
        map(StringFormatter.set_alphanumeric_snake_case, df.columns)
    )
    df = df.toDF(*formatted_columns)

    return df


def get_max_page_size(query_id, count_result_list):
    for d in count_result_list:
        if d["SQLQueries"] == query_id:
            return d["odata.maxpagesize"] + 1
    logger.error(f"m=get_max_page_size, msg=Did not find lines count for {query_id} query code.")
    raise Exception()


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("execution_date")

    args = parser.parse_args()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    execution_date = args.execution_date

    config_service = ConfigurationService(source[::-1])
    tables = config_service.get_config("tables")
    partitions_cols = config_service.get_config("partition_cols")

    logger.info(
        f"""
                m={JOB_NAME}, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
                execution_date={execution_date} msg=Starting spark job...
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    # Initializing clients
    spark_client = SparkClient()
    secrets = dbutils.secrets.get(scope="quintoandar", key=APIEnum.SAP)
    credentials = json.loads(secrets)
    sap_client = SapClient(
        credentials["username"], credentials["password"], credentials["company_db"]
    )
    sap_consumer = CONSUMERS["SapData"](client=sap_client)

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    logger.info(
        "m={JOB_NAME}, msg=Creating database in Spark Metastore if not exists..."
    )
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]
    spark_metastore_service.create_database(database_name)

    s3_loader = S3Loader()
    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")

    count_query_code = config_service.get_config("count_lines_query_code")
    extended_params = extend_incremental_params({}, execution_date)
    count_result_list = sap_consumer.sync(
        query_code=count_query_code, params=extended_params
    )

    for table_name in tables:
        table_config = tables[table_name]
        query_code = table_config["query_code"]
        schema_content = json.loads(table_config["schema_content"])
        params = table_config.get("params", {})

        extended_params = extend_incremental_params(params, execution_date)
        max_page_size = get_max_page_size(query_code, count_result_list)

        records = sap_consumer.sync(
            query_code=query_code, params=extended_params, max_page_size=max_page_size
        )

        if records:
            try:
                df = parse_records(records, schema_content)
                df = (
                    SparkDataFrameService()
                    .input(df)
                    .create_year_month_day_columns_from_date(dt_execution)
                    .output()
                )
                s3_loader.load_df(
                    df=df,
                    s3_path=f"{database_location}{table_name}",
                    format_options=format_options,
                    partitions=partitions_cols,
                )

                spark_metastore_loader.update_metastore(
                    df,
                    database_name,
                    table_name,
                    format_options,
                    database_location,
                    partitions_cols,
                    force_recreate=False,
                )

                spark_metastore_service.create_new_partitions_from_df(
                    database_name=database_name,
                    table_name=table_name,
                    df=df,
                    partition_cols=partitions_cols,
                )

                logger.info(
                    f"""m={JOB_NAME}, environment={environment}, source={source}, table_name={table_name},
                    schema_content={schema_content}. Tables successfully loaded into datalake!
                    """
                )

            except Exception as e:
                logger.error(
                    f"""m={JOB_NAME}, table_name={table_name}, schema_content={schema_content},
                    error_message={e}"""
                )
