from typing import List
from pyspark.sql import DataFrame

from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.loaders.spark_metastore_loader import SparkMetastoreLoader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.base.db import DatalakeMetastoreService
from quintoandar_logger import QuintoAndarLogger

LOGGER = QuintoAndarLogger(__name__)


class RawLayerLoader:
    """
    Orchestrates the loading of Spark DataFrames into the raw data lake layer.
    """

    def __init__(
        self,
        spark_client: SparkClient,
        environment: str,
        source: str,
        datalake_bucket: str,
        table_name: str,
        partition_cols: List[str],
        extraction_type: str = "full",
        logger: QuintoAndarLogger = LOGGER,
    ):
        """
        Initializes the RawLayerLoader.
        """
        self.logger = logger

        self.spark_client = spark_client
        self.environment = environment
        self.source = source
        self.datalake_bucket = datalake_bucket
        self.table_name = table_name
        self.partition_cols = partition_cols
        self.extraction_type = extraction_type.lower()

        self.metastore_service = SparkMetastoreService(spark_client)
        self.s3_loader = S3Loader()
        self.metastore_loader = SparkMetastoreLoader(self.metastore_service)

        self.db_info = DatalakeMetastoreService.get_db_info(
            self.environment, self.source, self.datalake_bucket
        )
        self.database_name = self.db_info["db_raw_databricks"]
        self.database_location = self.db_info["db_raw_path"]

        self.logger.info(
            f"RawLayerLoader initialized with the following configuration:\n"
            f"  Environment: {self.environment}\n"
            f"  Source: {self.source}\n"
            f"  Table Name: {self.table_name}\n"
            f"  Extraction Type: {self.extraction_type}\n"
            f"  Partitions: {self.partition_cols}\n"
            f"  Database Name: {self.database_name}\n"
            f"  Database Location: {self.database_location}"
        )

    def load_to_raw(self, df: DataFrame) -> None:
        """
        Orchestrates the process of loading the provided DataFrame into the raw data layer.
        """
        try:
            self._create_database_if_not_exists()
            self._load_df_to_s3(df)
            self._update_metastore(df)
            self._refresh_table()

        except Exception as e:
            self.logger.error(
                f"Error loading to raw layer for table {self.table_name}: {e}",
                exc_info=True,
            )
            raise

    def _create_database_if_not_exists(self) -> None:
        """
        Checks if the specified database exists in the metastore and creates it if it does not.
        """
        try:
            self.metastore_service.create_database(self.database_name)
        except Exception as e:
            self.logger.error(
                f"Error creating or checking database '{self.database_name}': {e}",
                exc_info=True,
            )
            raise

    def _load_df_to_s3(self, df: DataFrame) -> None:
        """
        Loads the provided Spark DataFrame to the specified S3 location.
        """
        s3_path = f"{self.database_location}{self.table_name}"
        format_options = SparkTableStorageFormat.DEFAULT_RAW
        mode = "overwrite" if self.extraction_type == "full" else "append"

        self.logger.info(
            f"Loading DataFrame to S3 with the following options:\n"
            f"  Path: {s3_path}\n"
            f"  Write Mode: {mode}\n"
            f"  Partitions: {self.partition_cols}\n"
            f"  Format: {format_options}"
        )

        try:
            self.s3_loader.load_df(
                df=df,
                s3_path=s3_path,
                format_options=format_options,
                partitions=self.partition_cols,
                mode=mode,
            )
        except Exception as e:
            self.logger.error(
                f"Error loading DataFrame to S3 path '{s3_path}': {e}", exc_info=True
            )
            raise

    def _update_metastore(self, df: DataFrame) -> None:
        """
        Updates the Hive metastore with the schema and location of the data.
        """
        format_options = SparkTableStorageFormat.DEFAULT_RAW

        try:
            self.metastore_loader.update_metastore(
                df=df,
                database_name=self.database_name,
                table_name=self.table_name,
                format_options=format_options,
                force_recreate=True,
                database_location=self.database_location,
                partitions=self.partition_cols,
            )
            self.logger.info(
                f"Metastore successfully updated for table '{self.database_name}.{self.table_name}'."
            )
        except Exception as e:
            self.logger.error(
                f"Error updating metastore for table '{self.database_name}.{self.table_name}': {e}",
                exc_info=True,
            )
            raise

    def _refresh_table(self) -> None:
        """
        Refreshes the metadata of the specified table in the Hive metastore.
        """
        try:
            self.metastore_service.refresh_table(self.database_name, self.table_name)
            self.logger.info(
                f"Table '{self.database_name}.{self.table_name}' refreshed successfully."
            )
        except Exception as e:
            self.logger.error(
                f"Error refreshing metastore table '{self.database_name}.{self.table_name}': {e}",
                exc_info=True,
            )
            raise
