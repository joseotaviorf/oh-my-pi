import logging
import sys
from argparse import ArgumentParser

from pyspark.sql import Window
from pyspark.sql.functions import lit, count, col, when
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import BaseDBUtils
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import DatabricksConsumer

JOB_NAME = "duplicity_test"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

base_dbutils = BaseDBUtils()
if base_dbutils.get_dbutils() is not None:
    dbutils = base_dbutils.get_dbutils()


def test_duplicity(schema, table):
    """
    Check if the table loaded to staging at S3 has no duplicity among its
     surrogate keys
    """
    logger.info(
        f"m=test_duplicity, schema={schema} table={table} msg=Validating duplicity."
    )

    query = f"select * from dw_{schema}_staging.{table}"

    df = get_staging_data(query)
    df = df.drop("ts_load") if "ts_load" in df.columns else df

    if is_fact(table):
        df = extract_fact_sk_columns(df)

    if has_duplicate_rows(df):
        raise AssertionError(
            f"m=test_duplicity, table={table}, msg=The table has duplicate rows."
        )

    logger.info(f"m=test_duplicity, table={table}, msg=The table has no duplicates.")

    assert True


def get_staging_data(query):
    databricks_consumer = DatabricksConsumer(
        conn_config={"db": "default"}, spark_client=SparkClient()
    )
    return databricks_consumer.get_data_from_query(query)


def has_duplicate_rows(df):
    window = Window.partitionBy(df.columns).rowsBetween(-sys.maxsize, sys.maxsize)
    df = df.withColumn(
        "test_control", when((count("*").over(window) > 1), "DUP").otherwise(lit("OK"))
    )
    df_errors = df.filter(col("test_control") != "OK")
    return df_errors.count() > 0


def is_sk_col(col_name):
    return col_name.startswith("sk_")


def extract_fact_sk_columns(df):
    sk_cols = [col for col in df.columns if is_sk_col(col)]
    return df.select(sk_cols)


def is_fact(table):
    return table.startswith("fact_")


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("schema")
    parser.add_argument("table_name")

    args = parser.parse_args()

    logger.info(
        f"m={JOB_NAME}, table_name={args.table_name}, msg=Job execution started."
    )

    test_duplicity(args.schema, args.table_name)

    logger.info(f"m={JOB_NAME}, msg=Test passed!")
