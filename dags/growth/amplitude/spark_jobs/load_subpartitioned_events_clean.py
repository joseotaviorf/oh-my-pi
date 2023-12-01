"""
    This job intends to increment events tables that are on the clean layer.
    There are some tables with name like: {id_app}_{event_type}_events that sums
    up informations from events table by id_app and event_type with some extractions.

    Since amplitude updates its values every day, we need to load those clean tables
    in order to update its values.
"""

from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from pyspark.sql import DataFrame

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.base.spark import SparkDataFrameService, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.loaders.spark_metastore_loader import SparkMetastoreLoader
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_subpartitioned_events_clean"

logger = QuintoAndarLogger(JOB_NAME)

parser = ArgumentParser(JOB_NAME)
parser.add_argument("execution_date")
parser.add_argument("env")
parser.add_argument("datalake_bucket")
parser.add_argument("source")
parser.add_argument("table")
parser.add_argument("--partition_by", nargs="+", dest="partition_by", required=False)


class AmplitudeCleanLoader():

    def __init__(
            self,
            env: str,
            source: str,
            layer: str,
            execution_date: datetime,
            datalake_bucket: str,
        ) -> None:

        self.env = env
        self.source = source
        self.layer = layer
        self.execution_date = execution_date
        self.datalake_bucket = datalake_bucket

        db_info = DatalakeMetastoreService.get_db_info(self.env, self.source, self.datalake_bucket)

        self.database_name = db_info["db_clean_databricks"]
        self.database_path = db_info["db_clean_path"]

        self.s3_loader = S3Loader()
        self.spark_client = SparkClient()
        self.spark_metastore_service = SparkMetastoreService(self.spark_client)
        self.spark_metastore_loader = SparkMetastoreLoader(self.spark_metastore_service)
        self.file_format = SparkTableStorageFormat.DEFAULT_CLEAN
    

    def fetch_data(self, table_name:str) -> DataFrame:
        """
        Function to fetch data from Ampltiude table clean query.
        """
        logger.info(
            f"m=__main__, date={self.execution_date}, source={self.source}, "
            f"table_name={table_name}, msg=Retrieving records..."
        )

        query = DAGPackagesPathService.get_query_file_content_in_spark_jobs(
            dag_name=self.source, table_name=table_name, layer=self.layer
        ).format(self.execution_date.year, self.execution_date.month, self.execution_date.day)

        df = self.spark_client.get_records(query)

        df_cols = df.columns

        if('id_schema' in df.columns):
            df = df.withColumn("id_schema",df.id_schema.cast('bigint'))

        if('location_lat' in df.columns):
            df = df.withColumn("location_lat",df.id_schema.cast('string'))

        if('location_lng' in df.columns):
            df = df.withColumn("location_lng",df.id_schema.cast('string'))

        df = df.select(df_cols)

        return df 

    def load_data_into_datalake(
            self, 
            df: DataFrame, 
            table_name: str, 
            partition_by: list
        ):

        logger.info(
            f"m=__main__, date={self.execution_date}, source={self.source}, "
            f"table_name={table_name}, msg=Loading records into datalake..."
        )

        df = (
            SparkDataFrameService(df)
            .optimize_partitions_by_partition_columns(partition_by)
            .output()
        )

        self.s3_loader.load_df(
            df=df,
            s3_path=f"{self.database_path}{table_name}",
            format_options=self.file_format,
            optimize_dataframe=False,
            partitions=partition_by,
        )
        self.spark_metastore_loader.update_metastore(
            df=df,
            database_name=self.database_name,
            table_name=table_name,
            format_options=self.file_format,
            database_location=self.database_path,
            partitions=partition_by,
        )

if __name__ == "__main__":
    args = parser.parse_args()
    execution_date = args.execution_date
    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table
    partition_by = args.partition_by

    logger.info(
        f"m=__main__, date={execution_date}, source={source}, "
        f"partition_by={str(partition_by)}, msg=Job started"
    )

    execution_date = datetime.strptime(execution_date, "%Y-%m-%d")

    amplitude_clean_loader = AmplitudeCleanLoader(
        env=env, 
        source=source,
        layer="clean",
        execution_date=execution_date,
        datalake_bucket=datalake_bucket
    )

    # fetch Amplitude cean tables args
    table_args = (amplitude_clean_loader.fetch_data(table_name), table_name, partition_by)

    # load Amplitude clean data into datalake
    amplitude_clean_loader.load_data_into_datalake(*table_args)