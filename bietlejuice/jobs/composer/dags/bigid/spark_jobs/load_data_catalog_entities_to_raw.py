import json
import logging
from argparse import ArgumentParser

from pyspark import Row
from quintoandar_logger import QuintoAndarLogger
from quintoandar_bigid_api_client.clients import BigidClient
from quintoandar_bigid_api_client.consumers import CONSUMERS

from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.api.api_enum import APIEnum

from bietlejuice.jobs.composer.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
    SparkDataFrameService,
)

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_full_data_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def fetch_bigid_source_entities(host, username, password, database_types: set):
    client = BigidClient(username=username, password=password, api_base_url=host)
    datasources_consumer = CONSUMERS["Datasources"](
        client=client, database_types=database_types
    )
    tables_consumer = CONSUMERS["Tables"](client=client)
    columns_consumer = CONSUMERS["Columns"](client=client)

    results = {}
    for ds_name in datasources_consumer.sync():
        results[ds_name] = {}
        for tb_name in tables_consumer.sync(ds_name):
            columns = columns_consumer.sync(tb_name)
            results[ds_name][tb_name] = columns
    return results


def create_df_from_results(results, spark_client):
    rows = []
    for ds in results:
        for table in results[ds]:
            for column, column_attributes in results[ds][table].items():
                rows.append(
                    Row(
                        datasource=ds,
                        table_full_qualified_name=table,
                        column_name=column,
                        data_type=column_attributes["type"],
                        classifications=column_attributes["classifications"],
                    )
                )
    return spark_client.create_dataframe(rows)


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the API")
    parser.add_argument("table_name", help="table name to be created")
    parser.add_argument("execution_date", help="execution date in str format")
    parser.add_argument(
        "--database_types",
        help="database types to be fetched by datasources consumer",
        nargs="+",
    )

    args = parser.parse_args()

    environment = args.environment
    source = args.source
    datalake_bucket = args.datalake_bucket
    table_name = args.table_name
    database_types = args.database_types

    logger.info(
        f"m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket}, "
        f"table_name={table_name}, msg=Starting spark job..."
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    json_credentials = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key=APIEnum.BIGID)
    credentials = json.loads(json_credentials)
    bigid_source_entities = fetch_bigid_source_entities(
        credentials["host"],
        credentials["username"],
        credentials["password"],
        database_types,
    )

    spark_client = SparkClient()
    df = create_df_from_results(bigid_source_entities, spark_client)

    df = SparkDataFrameService().input(df).convert_array_type_to_json().output()

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    metastore_service = SparkMetastoreService(spark_client)
    metastore_service.create_database(database_name)

    s3_loader = S3Loader()
    s3_loader.load_df(
        df=df, s3_path=f"{database_location}{table_name}", format_options=format_options
    )

    spark_metastore_loader = SparkMetastoreLoader(metastore_service)
    spark_metastore_loader.update_metastore(
        df, database_name, table_name, format_options, database_location
    )
    metastore_service.refresh_table(database_name, table_name)
