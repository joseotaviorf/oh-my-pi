import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import BaseDBUtils
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import DatabricksConsumer

JOB_NAME = "emptiness_test"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

base_dbutils = BaseDBUtils()
if base_dbutils.get_dbutils() is not None:
    dbutils = base_dbutils.get_dbutils()


def get_staging_data(query):
    databricks_consumer = DatabricksConsumer(
        conn_config={"db": "default"}, spark_client=SparkClient()
    )
    return databricks_consumer.get_data_from_query(query)


def test_emptiness(schema, table):
    """
    Check if the table loaded to staging at S3 is empty
    """
    query = f"select count(1) from dw_{schema}_staging.{table}"

    df = get_staging_data(query)
    result_count = df.collect()[0][0]

    logger.info(
        f"m=test_emptiness, schema={schema} table={table} msg=Validating counts."
    )

    if result_count == 0:
        raise AssertionError(
            "m=test_emptiness "
            f"result_count={result_count}, "
            "msg=The table is empty."
        )

    logger.info(
        "m=test_emptiness "
        f"result_count={result_count}, "
        "msg=The table is not empty."
    )

    assert True


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("schema")
    parser.add_argument("table_name")

    args = parser.parse_args()

    logger.info(
        f"m={JOB_NAME}, table_name={args.table_name}, msg=Job execution started."
    )

    test_emptiness(args.schema, args.table_name)

    logger.info(f"m=emptiness_test, msg=Test passed!")
