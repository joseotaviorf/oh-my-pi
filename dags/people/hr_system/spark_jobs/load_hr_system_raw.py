import json
import argparse
from multiprocessing import Pool
from datetime import datetime, timedelta
from pyspark.sql.types import StructType
from pyspark.sql.functions import current_timestamp, date_format, col, lit
from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.base.api.api_enum import APIEnum
from quintoandar_hr_system_api_client.services import EndPointService
from quintoandar_hr_system_api_client.clients.hr_system_client import HrSystemClient
from quintoandar_hr_system_api_client.consumers import get_consumer

DATABRICKS_SCOPE = "people"
JOB_NAME = "load_hr_system_raw"
logger = QuintoAndarLogger(JOB_NAME)


class Ingestion:
    def __init__(self, args, url, token) -> None:
        self.environment = args.environment
        self.datalake_bucket = args.datalake_bucket
        self.source = args.source
        self.table_name = args.endpoint_id
        self.endpoint_id = args.endpoint_id.replace("_", "").upper()
        self.execution_date = datetime.strptime(args.execution_date, "%Y-%m-%d")
        self.partition_cols = json.loads(args.partition_cols)
        self.extraction_type = args.extraction_type
        self.load_start_date = datetime.strptime(args.load_start_date, "%Y-%m-%d")
        self.load_end_date = datetime.strptime(
            args.load_end_date, "%Y-%m-%d"
        ) + timedelta(days=1)
        self.endpoint_details = self.treat_params(args.endpoint_details)
        self.has_dt_effective = self.endpoint_details.get("has_dt_effective", False)
        self.offsets = self.define_offset()
        self.client = HrSystemClient(api_url=url, api_token=token)
        self.consumer = get_consumer(self.client, self.endpoint_id)
        self.deduplication_key = self.endpoint_details.get("deduplication_key", None)
        self.has_columns_to_delete = self.endpoint_details.get(
            "has_columns_to_delete", None
        )
        self.columns_to_delete = self.endpoint_details.get("columns_to_delete", None)
        self.column_to_partition = self.endpoint_details.get(
            "column_to_partition", None
        )

    def treat_params(self, endpoint_details):
        endpoint_details = json.loads(endpoint_details)
        endpoint_details["params"] = json.loads(endpoint_details["params"])
        return endpoint_details

    def define_offset(self):
        offsets_number = {
            (self.endpoint_details.get("future_offset", None), 1),
            (self.endpoint_details.get("past_offset", None), -1),
        }
        offsets = [self.execution_date]
        for offset in offsets_number:
            if offset[0] is not None:
                days_offset = int(offset[0]) * offset[1]
                offset_date = self.execution_date + timedelta(days=days_offset)
                offsets.append(offset_date)
        return offsets

    def get_data_from_api(self, list_ingestion_tables):
        arguments = list()
        for ingestion_table in list_ingestion_tables:
            aux_arguments = (ingestion_table, self.deduplication_key)
            arguments.append(aux_arguments)
        with Pool(len(arguments)) as p:
            json_data = p.starmap(run_sync, arguments)
        return json_data

    def create_spark_dataframe(self, dt_data):
        spark_schema = EndPointService.get_spark_schema(self.consumer.path, self.client)
        schema = StructType.fromJson(spark_schema)
        return spark_client.create_dataframe(dt_data, schema=schema)

    def get_df(self, json_data):
        dfs = list()
        for data in json_data:
            for dt_effective in data:
                dt_data = data[dt_effective]
                df = self.create_spark_dataframe(dt_data)
                df = self.delete_columns(df)
                df = self.insert_columns(df, dt_effective)
                df = self.insert_partitions(df)
                dfs.append(df)
        return dfs

    def delete_columns(self, df):
        if self.columns_to_delete:
            spark.conf.set("spark.sql.caseSensitive", True)
            for column in self.columns_to_delete:
                df = df.drop(column)
            spark.conf.set("spark.sql.caseSensitive", False)
            return df
        return df

    def insert_columns(self, df, dt_effective=None):
        df = df.withColumn("ts_load", current_timestamp())
        if self.has_dt_effective:
            df = df.withColumn("dt_effective", lit(dt_effective.replace("-", "")))
        return df

    def insert_partitions(self, df):
        if self.partition_cols:
            df = df.withColumn(
                "year", date_format(col(self.column_to_partition), "yyyy")
            )
            df = df.withColumn(
                "month", date_format(col(self.column_to_partition), "MM")
            )
            df = df.withColumn("day", date_format(col(self.column_to_partition), "dd"))
            return df
        return df

    def load_raw(self, df, spark_client):
        db_info = DatalakeMetastoreService.get_db_info(
            self.environment, self.source, self.datalake_bucket
        )
        database_name = db_info["db_raw_databricks"]
        format_options = SparkTableStorageFormat.DEFAULT_RAW
        database_location = db_info["db_raw_path"]
        logger.info(
            f"m={JOB_NAME}, msg=Creating database in Spark Metastore if not exists..."
        )
        metastore_service = SparkMetastoreService(spark_client)
        metastore_service.create_database(database_name)
        s3_loader = S3Loader()
        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{self.table_name}",
            format_options=format_options,
            partitions=self.partition_cols,
        )
        spark_metastore_loader = SparkMetastoreLoader(metastore_service)
        spark_metastore_loader.update_metastore(
            df=df,
            database_name=database_name,
            table_name=self.table_name,
            format_options=format_options,
            force_recreate=True,
            database_location=database_location,
            partitions=self.partition_cols,
        )
        metastore_service.refresh_table(database_name, self.table_name)

    def clear_directory(self, layer):
        if self.has_dt_effective == True:
            dbutils.fs.rm(
                f"s3://{self.datalake_bucket}/{layer}/{self.source}/{self.table_name}/",
                True,
            )


class IngestionTable:
    def __init__(self, ingestion: Ingestion, dt_effective: datetime) -> None:
        self.ingestion = ingestion
        self.dt_effective = dt_effective.strftime("%Y-%m-%d")
        self.table_name = ingestion.endpoint_id
        self.params = ingestion.endpoint_details["params"].copy()
        self.define_params()
        self.consumer = get_consumer(ingestion.client, ingestion.endpoint_id)

    def define_params(self):
        if ingestion.has_dt_effective:
            self.params["effectiveDate"] = self.dt_effective
        if self.ingestion.extraction_type == "incremental":
            load_start_date = self.ingestion.load_start_date.strftime(
                "%Y-%m-%dT00:00:00"
            )
            load_end_date = self.ingestion.load_end_date.strftime("%Y-%m-%dT00:00:00")
            self.params["q"] = f"LastUpdateDate>={load_start_date} and <{load_end_date}"


def get_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("endpoint_id", help="endpoint_id/name of the table")
    parser.add_argument("execution_date", help="execution date in str format")
    parser.add_argument("partition_cols")
    parser.add_argument("extraction_type")
    parser.add_argument("load_start_date")
    parser.add_argument("load_end_date")
    parser.add_argument("endpoint_details")
    return parser


def get_conn_config() -> tuple[str, str]:
    """Returns the connection configuration from Databricks Secrets."""

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        global dbutils
        dbutils = base_dbutils.get_dbutils()
    json_credentials = dbutils.secrets.get(
        scope=DATABRICKS_SCOPE, key=APIEnum.HR_SYSTEM
    )
    credentials = json.loads(json_credentials)
    url = credentials["url"]
    token = credentials["token"]

    return url, token


def run_sync(ingestion_table, deduplication_key):
    logger.info(
        f"m={JOB_NAME}, msg=Endpoint Details {ingestion_table.ingestion.endpoint_details}"
    )
    return {
        ingestion_table.dt_effective: ingestion_table.consumer.sync(
            params=ingestion_table.params, deduplication_key=deduplication_key
        )
    }


if __name__ == "__main__":
    parser = get_parser()
    args = parser.parse_args()
    url, token = get_conn_config()
    ingestion = Ingestion(args, url, token)
    spark_client = SparkClient()
    logger.info(
        f"m={JOB_NAME}, environment={ingestion.environment}, source={ingestion.source}, datalake_bucket={ingestion.datalake_bucket}, "
        f"table_name={ingestion.endpoint_id}, msg=Starting spark job..."
    )
    list_ingestion_tables = list()
    for offset in ingestion.offsets:
        ingestion_table = IngestionTable(ingestion, offset)
        list_ingestion_tables.append(ingestion_table)
    json_data = ingestion.get_data_from_api(list_ingestion_tables)
    dfs = ingestion.get_df(json_data)
    ingestion.clear_directory("raw")
    for df in dfs:
        ingestion.load_raw(df, spark_client)
    ingestion.clear_directory("clean")
    logger.info(f"m={JOB_NAME}, msg=Spark job finished.")
