from typing import List
from pyspark.sql import DataFrame

from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.loaders.spark_metastore_loader import SparkMetastoreLoader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.databricks.table_privileges import TablePrivileges
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

        Args:
            spark_client (SparkClient): The Spark client instance.
            environment (str): The environment (e.g., forno, prod).
            source (str): The data source identifier.
            datalake_bucket (str): The target S3 bucket name.
            table_name (str): The name of the table to load.
            partition_cols (List[str]): A list of partition column names.
            extraction_type (str, optional): The type of extraction ("full" or "incremental"). Defaults to "full".
            logger (QuintoAndarLogger, optional): The logger instance. Defaults to LOGGER.
        """
        self.spark_client = spark_client
        self.environment = environment
        self.source = source
        self.datalake_bucket = datalake_bucket
        self.table_name = table_name
        self.partition_cols = partition_cols
        self.extraction_type = extraction_type.lower()
        self.logger = logger
        self.metastore_service = SparkMetastoreService(spark_client)
        self.s3_loader = S3Loader()
        self.metastore_loader = SparkMetastoreLoader(self.metastore_service)

        self.db_info = DatalakeMetastoreService.get_db_info(
            self.environment, self.source, self.datalake_bucket
        )
        self.database_name = self.db_info["db_raw_databricks"]
        self.database_location = self.db_info["db_raw_path"]

        self.table_privileges = TablePrivileges.from_environment_default(
            f"{self.database_name}.{self.table_name}"
        )

    def load_to_raw(self, df: DataFrame) -> None:
        """
        Orchestrates the process of loading the provided DataFrame into the raw data
        layer. This includes creating the database, writing the DataFrame to S3,
        updating the metastore, refreshing the table, and granting access permissions.

        Args:
            df (DataFrame): The Spark DataFrame to be loaded into the raw layer.
        """
        if df.isEmpty():
            self.logger.warning(
                f"Input DataFrame for table '{self.table_name}' is empty. Skipping load process."
            )
            return

        try:
            self._create_database_if_not_exists()
            self._load_df_to_s3(df)
            self._update_metastore(df)
            self._refresh_table()
            self._grant_table_permissions()
        except Exception as e:
            self.logger.error(
                f"Failed to load data to raw layer for table '{self.table_name}'. Error: {e}",
                exc_info=True,
            )
            raise

    def _create_database_if_not_exists(self) -> None:
        """
        Creates the database in the metastore if it does not already exist.
        """
        try:
            self.logger.info(f"Ensuring database '{self.database_name}' exists.")
            self.metastore_service.create_database(self.database_name)
        except Exception as e:
            self.logger.error(
                f"Error creating database '{self.database_name}': {e}", exc_info=True
            )
            raise

    def _load_df_to_s3(self, df: DataFrame) -> None:
        """
        Loads the DataFrame to the specified S3 location.
        """
        s3_path = f"{self.database_location}{self.table_name}"
        format_options = SparkTableStorageFormat.DEFAULT_RAW
        mode = "overwrite" if self.extraction_type == "full" else "append"

        self.logger.info(
            f"Loading DataFrame to S3 path '{s3_path}' with mode '{mode}' and partitions {self.partition_cols}."
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
        self.logger.info(
            f"Updating metastore for table '{self.database_name}.{self.table_name}'."
        )
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
        except Exception as e:
            self.logger.error(
                f"Error updating metastore for table '{self.table_name}': {e}",
                exc_info=True,
            )
            raise

    def _refresh_table(self) -> None:
        """
        Refreshes the metadata of the specified table in the Hive metastore.
        """
        self.logger.info(f"Refreshing table '{self.database_name}.{self.table_name}'.")
        try:
            self.metastore_service.refresh_table(self.database_name, self.table_name)
        except Exception as e:
            self.logger.error(
                f"Error refreshing table '{self.table_name}': {e}", exc_info=True
            )
            raise

    def _grant_table_permissions(self) -> None:
        """
        Applies the defined table privileges using the provided TablePrivileges object.
        """
        if self.table_privileges:
            self.logger.info(
                f"Applying table privileges for {self.table_privileges.table_name}"
            )
            try:
                self.table_privileges.apply()
                self.logger.info("Successfully applied table privileges.")
            except Exception as e:
                self.logger.warning(
                    f"Could not apply table privileges for {self.table_privileges.table_name}. "
                    f"This might be a non-critical error. Details: {e}"
                )
        else:
            self.logger.info(
                "No TablePrivileges object provided, skipping permission grants."
            )
