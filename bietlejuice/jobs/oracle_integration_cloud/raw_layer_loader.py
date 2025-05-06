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
        partition_cols: str,
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
            partition_cols (str): Comma-separated string of partition columns.
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

    def load_to_raw(self, df: DataFrame) -> None:
        """
        Orchestrates the process of loading the provided DataFrame into the raw data
        layer. This includes creating the database if it doesn't exist, writing the
        DataFrame to S3, updating the Hive metastore with the new data, and refreshing
        the corresponding table for query availability.

        Args:
            df (DataFrame): The Spark DataFrame to be loaded into the raw layer.

        Raises:
            Exception: If any error occurs during the database creation, data loading
                    to S3, metastore update, or table refresh steps. Specific
                    details of the error will be logged.
        """
        try:
            self._create_database_if_not_exists()
            self._load_df_to_s3(df)
            self._update_metastore(df)
            self._refresh_table()
        except Exception as e:
            self.logger.error(f"Error loading to raw layer: {e}")
            raise

    def _create_database_if_not_exists(self) -> None:
        """
        Checks if the specified database exists in the metastore and creates it
        if it does not. Logs the attempt and any potential errors.

        Raises:
            Exception: If an error occurs during the database creation process
                    in the metastore service.
        """
        try:
            self.metastore_service.create_database(self.database_name)
        except Exception as e:
            self.logger.error(f"Error creating database: {e}")
            raise

    def _load_df_to_s3(self, df: DataFrame) -> None:
        """
        Loads the provided Spark DataFrame to the specified S3 location.
        The storage format and write mode (overwrite for full loads, append for
        incremental loads) are determined based on the configuration. The data
        is partitioned according to the configured partition columns.

        Args:
            df (DataFrame): The Spark DataFrame to be loaded to S3.

        Raises:
            Exception: If any error occurs during the process of loading the
                    DataFrame to S3, including issues with the S3 loader service.
        """
        s3_path = f"{self.database_location}{self.table_name}"
        format_options = SparkTableStorageFormat.DEFAULT_RAW
        mode = "overwrite" if self.extraction_type == "full" else "append"
        try:
            self.s3_loader.load_df(
                df=df,
                s3_path=s3_path,
                format_options=format_options,
                partitions=self.partition_cols,
                mode=mode,
            )
        except Exception as e:
            self.logger.error(f"Error loading DataFrame to S3: {e}")
            raise

    def _update_metastore(self, df: DataFrame) -> None:
        """
        Updates the Hive metastore with the schema and location of the data loaded
        into S3. This ensures that the table is properly defined and queryable by
        Spark SQL or other data access tools. It forces a recreation of the table
        metadata to ensure consistency.

        Args:
            df (DataFrame): A sample Spark DataFrame representing the schema of the
                        data that was loaded to S3. This DataFrame is used to infer
                        the column names and data types for the metastore table.

        Raises:
            Exception: If any error occurs during the metastore update process,
                    including issues communicating with the metastore service.
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
        except Exception as e:
            self.logger.error(f"Error updating metastore: {e}")
            raise

    def _refresh_table(self) -> None:
        """
        Refreshes the metadata of the specified table in the Hive metastore.
        This operation ensures that the metastore has the most up-to-date information
        about the table's schema and data location, especially after new data has
        been loaded or partitions have been added.

        Raises:
            Exception: If an error occurs while attempting to refresh the table
                    metadata in the metastore service.
        """
        try:
            self.metastore_service.refresh_table(self.database_name, self.table_name)
        except Exception as e:
            self.logger.error(f"Error refreshing metastore table: {e}")
            raise
