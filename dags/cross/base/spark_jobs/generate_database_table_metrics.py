import json
import logging
from argparse import ArgumentParser, Namespace

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.db_consumers import MySqlConsumer, PostgresConsumer
from bietlejuice.pipeline.delta_table_loader_pipeline import DeltaTableLoaderPipeline
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "generate_database_table_metrics"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def parse_arguments() -> Namespace:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("dbutils_secret_key")
    parser.add_argument("schema")
    parser.add_argument("table_name")
    parser.add_argument("execution_date")
    parser.add_argument("db_schema")
    parser.add_argument("get_table_metrics")
    parser.add_argument("dag_id")
    parser.add_argument("db_type", type=str, help="mysql/postgres")
    return parser.parse_args()


def get_conn_config(dbutils_secret_key: str) -> dict:
    """Returns the connection configuration from Databricks Secrets."""

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        global dbutils
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(scope="quintoandar", key=dbutils_secret_key)

    return json.loads(conn_config_json)


def main():
    args = parse_arguments()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    dbutils_secret_key = args.dbutils_secret_key
    schema = args.schema
    table_name = args.table_name
    partition_cols = ['year', 'month', 'day', 'dag_id']
    execution_date = args.execution_date
    db_schema = args.db_schema
    get_table_metrics = json.loads(args.get_table_metrics)
    dag_id = args.dag_id
    db_type = args.db_type

    logger.info(
        f"""
        m=__main__, environment={environment}, dbutils_secret_key={dbutils_secret_key}, datalake_bucket={datalake_bucket},
        schema={schema}, table_name={table_name},
        partition_cols={partition_cols}, execution_date={execution_date},
        db_schema={db_schema}
        msg=Starting spark job...
        """
    )

    conn_config = get_conn_config(dbutils_secret_key)
    conn_config["schema"] = db_schema
    spark_client = SparkClient()
    if db_type == "postgres":
        consumer = PostgresConsumer(conn_config, spark_client)
    else:
        consumer = MySqlConsumer(conn_config, spark_client)

    format_options = SparkTableStorageFormat.DEFAULT_CLEAN

    db_info = DatalakeMetastoreService.get_db_info(environment, schema, datalake_bucket)
    database_name = db_info["db_clean_databricks"]
    database_location = db_info["db_clean_path"]

    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)

    db_name = dbutils_secret_key

    if db_type == "postgres":
        query_template = """
        SELECT
            '{dag_id}' AS dag_id,
            '{db_name}' AS db_name,
            '{product_table_name}' AS db_table_name,
            '{clean_table_name}' AS clean_table_name,
            CAST({metric_value} AS VARCHAR) AS metric_value,
            '{metric_name}' AS metric_name,
            PG_TYPEOF({metric_value}) AS metric_data_type,
            '{execution_date}' AS dt_execution,
            CAST(EXTRACT(YEAR FROM DATE('{execution_date}')) AS INT) AS year,
            CAST(EXTRACT(MONTH FROM DATE('{execution_date}')) AS INT) AS month,
            CAST(EXTRACT(DAY FROM DATE('{execution_date}')) AS INT) AS day
        FROM
            "{product_table_name}"
        """
    else:
        query_template = """
        SELECT
            '{dag_id}' AS dag_id,
            '{db_name}' AS db_name,
            '{product_table_name}' AS db_table_name,
            '{clean_table_name}' AS clean_table_name,
            CAST({metric_value} AS CHAR) AS metric_value,
            '{metric_value}' AS metric_name,
            '{execution_date}' AS dt_execution,
            YEAR('{execution_date}') AS year,
            MONTH('{execution_date}') AS month,
            DAY('{execution_date}') AS day
        FROM
            `{product_table_name}`
        """

    query = []
    for db_table_name, table_information in get_table_metrics.items():
        clean_table_name = table_information["clean_table_name"]
        for metric_name, metric_value in table_information["metrics"].items():
            query.append(query_template.format(execution_date=execution_date, db_name=db_name, product_table_name=db_table_name, clean_table_name=clean_table_name, metric_value=f'{metric_name}({metric_value})', metric_name=f'{metric_name}_{metric_value}', dag_id=dag_id))

    union_all_query = '\nUNION ALL\n'.join(query)
    df_metrics = consumer.get_data_from_query(union_all_query)

    DeltaTableLoaderPipeline(
        database_name,
        table_name.lower(),
        database_location,
        LayerEnum.CLEAN,
        None,
        partition_cols,
        spark=spark
    ).load_and_register(df_metrics, format_options)


if __name__ == "__main__":
    main()
