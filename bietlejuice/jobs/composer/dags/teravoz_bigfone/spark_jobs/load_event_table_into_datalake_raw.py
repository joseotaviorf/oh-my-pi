import json
import logging
from argparse import ArgumentParser

from collections import OrderedDict
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.consumers import PostgreSQLConsumer
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreInfo
from bietlejuice.jobs.composer.base.spark import (
    BaseDBUtils,
    BaseSparkContext,
    SparkMetastoreService,
    SparkTableStorageFormat,
)
from bietlejuice.jobs.composer.loaders import SparkDataframeIntoDatalakeLoader
from bietlejuice.jobs.composer.wrappers import SparkSQLClient

DATABRICKS_SCOPE = "quintoandar"

JOB_NAME = "load_teravoz_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

spark, sqlContext = BaseSparkContext.spark, BaseSparkContext.sqlContext

if __name__ == "__main__":

    parser = ArgumentParser(description="load_teravoz_into_datalake")

    # args passed by Airflow task
    parser.add_argument("table_name", type=str, help="spark table name")
    parser.add_argument("environment", type=str, help="forno/prod values")
    parser.add_argument("execution_date", type=str, help="execution date in str format")

    args = parser.parse_args()

    logger.info(
        "m=load_teravoz_into_datalake_raw, table_name={}, execution_date={}, environment={}, msg=print args spark jobs params".format(
            args.table_name, args.execution_date, args.environment
        )
    )

    execution_date = args.execution_date
    environment = args.environment
    table_name = args.table_name

    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
    partitions = OrderedDict(
        [
            ("year", int(dt_execution.year)),
            ("month", int(dt_execution.month)),
            ("day", int(dt_execution.day)),
        ]
    )

    with open(table_name, "r") as f:
        query = f.read()

    # start Spark Session
    base_dbutils = BaseDBUtils()

    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    # get BigFone credentials stored in Databricks secrets
    json_connection = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key="bigfone")

    # establish connection and get data from Event table
    connection = json.loads(json_connection)
    consumer = PostgreSQLConsumer(connection)
    event_table_data = consumer.get_data_from_query(query.format(**partitions))

    datalake_info = DatalakeMetastoreInfo().get_db_info("forno", "bigfone")

    # get spark client
    spark_sql_client = SparkSQLClient(spark, sqlContext)
    spark_service = SparkMetastoreService(
        datalake_info["db_raw_databricks"],
        datalake_info["db_raw_path"],
        spark_sql_client,
    )

    # loaders
    loader = SparkDataframeIntoDatalakeLoader(
        format=SparkTableStorageFormat.DEFAULT_RAW, metastore_service=spark_service
    )
    loader.overwrite_partition(
        df=event_table_data,
        partition_by_list=list(partitions.keys()),
        table_name=table_name,
        schema_merging=True,
    )

    # create partition into spark table
    spark_service.create_new_partitions_from_df(
        table_name=table_name,
        df=event_table_data,
        partition_by_list=list(partitions.keys()),
    )
