from typing import List

from pyspark.sql import DataFrame
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.db.datalake_metastore_service import DatalakeMetastoreService
from bietlejuice.base.spark.spark_table_storage_format import SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.metastore_loader_factory import MetastoreLoaderFactory
from bietlejuice.loaders.s3_loader import S3Loader

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
        self.s3_loader = S3Loader()
        self.metastore_loader = MetastoreLoaderFactory.create(spark_client)
        self.metastore_service = self.metastore_loader.metastore_service

        self.db_info = DatalakeMetastoreService.get_db_info(
            self.environment, self.source, self.datalake_bucket
        )
        self.database_name = self.db_info["db_raw_databricks"]
        self.database_location = self.db_info["db_raw_path"]

    def load_to_raw(
        self,
        df: DataFrame,
        *,
        metastore_force_recreate: bool = True,
        apply_table_privileges: bool = True,
        refresh_table_after_load: bool = True,
    ) -> None:
        """
        Orchestrates loading the DataFrame into the raw data layer: database creation,
        S3 write, metastore update, optional grants, and optional table refresh.

        For streaming incremental loads (multiple append batches in one job), callers
        may set ``metastore_force_recreate=False``, ``apply_table_privileges=False``,
        and ``refresh_table_after_load=False`` on intermediate batches, then call
        :meth:`finalize_raw_layer_visibility` once at the end to grant privileges and
        refresh Unity Catalog metadata (avoids expensive per-batch ``REFRESH TABLE``).

        Args:
            df (DataFrame): Spark DataFrame to load into the raw layer.
            metastore_force_recreate (bool): When True, always recreates the metastore
                table from the DataFrame schema. When False, merges schema if the table
                exists or creates it if missing. Defaults to True for backward
                compatibility.
            apply_table_privileges (bool): When True, applies configured table
                privileges after the metastore update. Defaults to True.
            refresh_table_after_load (bool): When True, runs ``REFRESH TABLE`` after
                load. Defaults to True.
        """
        if df.isEmpty():
            self.logger.warning(
                f"Input DataFrame for table '{self.table_name}' is empty. Skipping load process."
            )
            return

        try:
            self._create_database_if_not_exists()
            self._load_df_to_s3(df)
            self._update_metastore(df, force_recreate=metastore_force_recreate)
            if apply_table_privileges:
                self._apply_privileges_to_people_team()
            if refresh_table_after_load:
                self._refresh_table()
        except Exception as e:
            self.logger.error(
                f"Failed to load data to raw layer for table '{self.table_name}'. Error: {e}",
                exc_info=True,
            )
            raise

    def finalize_raw_layer_visibility(self) -> None:
        """
        Applies table privileges and refreshes metastore metadata after one or more
        incremental loads that deferred grants and refresh via :meth:`load_to_raw`.
        """
        self._apply_privileges_to_people_team()
        self._refresh_table()

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
                write_mode=mode,
            )
        except Exception as e:
            self.logger.error(
                f"Error loading DataFrame to S3 path '{s3_path}': {e}", exc_info=True
            )
            raise

    def _update_metastore(self, df: DataFrame, force_recreate: bool = True) -> None:
        """
        Updates the Hive metastore with the schema and location of the data.

        Args:
            df (DataFrame): Sample DataFrame for schema and metastore alignment.
            force_recreate (bool): Passed to the metastore loader; False enables
                merge-in-place when the table already exists and schemas match.
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
                force_recreate=force_recreate,
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

    def _apply_privileges_to_people_team(self) -> None:
        """Applies specific table privileges for the 'people-analytics' role.

        This method grants ALL PRIVILEGES
        on the current table to the 'people-analytics' role."""

        table_privileges_dict = {"people-analytics": ["ALL PRIVILEGES"]}

        try:
            full_table_name = f"{self.database_name}.{self.table_name}"
            table_privileges = TablePrivileges.from_input_dict(
                table_privileges_dict, full_table_name
            )
            table_privileges.apply()
            self.logger.info(
                f"Successfully applied privileges on {full_table_name} for 'people-analytics'."
            )
        except Exception as e:
            self.logger.error(f"Failed to apply privileges on {full_table_name}: {e}")
