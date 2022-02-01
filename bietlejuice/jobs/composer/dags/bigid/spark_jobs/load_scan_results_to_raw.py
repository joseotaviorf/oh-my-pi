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


def fetch_bigid_source_scans_result(host, username, password):
    client = BigidClient(username=username, password=password, api_base_url=host)

    scans_result_consumer = CONSUMERS["ScansResult"](client=client)
    results = scans_result_consumer.sync()

    return results


def create_df_from_results(results, spark_client):
    rows = []
    for scan in results:
        rows.append(
            Row(
                _id=str(scan.get("_id")),
                hashId=str(scan.get("hashId")),
                attribute=str(scan.get("attribute")),
                attributeRecordsCount=str(scan.get("attributeRecordsCount")),
                avgRisk=str(scan.get("avgRisk")),
                fieldName=str(scan.get("fieldName")),
                object=str(scan.get("object")),
                owner=str(scan.get("owner")),
                source=str(scan.get("source")),
                update_date=str(scan.get("update_date")),
                pii_investigation_join_field=str(
                    scan.get("pii_investigation_join_field")
                ),
                attribute_original_name=str(scan.get("attribute_original_name")),
                attribute_name=str(scan.get("attribute_name")),
                tags=str(scan.get("tags")),
                comment=str(scan.get("comment")),
                type=str(scan.get("type")),
                last_scan_at=str(scan.get("last_scan_at")),
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

    logger.info(
        f"m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket}, "
        f"table_name={table_name}, msg=Starting spark job..."
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    json_credentials = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key=APIEnum.BIGID)
    credentials = json.loads(json_credentials)
    bigid_source_scans_result = fetch_bigid_source_scans_result(
        credentials["host"], credentials["username"], credentials["password"]
    )

    spark_client = SparkClient()
    df = create_df_from_results(bigid_source_scans_result, spark_client)

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
