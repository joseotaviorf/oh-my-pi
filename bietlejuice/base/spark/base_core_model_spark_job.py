import logging
import json
from abc import ABC, abstractmethod
from argparse import ArgumentParser
from typing import Any
from quintoandar_logger import QuintoAndarLogger

from pyspark.sql import SparkSession, DataFrame

from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.pipeline.dataframe_delta_table_loader_pipeline import (
    DataFrameDeltaTableLoaderPipeline,
)
from bietlejuice.services.configuration_service import ConfigurationService


class BaseCoreModelSparkJob(ABC):
    """Abstract base class for core model Spark jobs."""

    def __init__(self, job_name: str):
        """
        Initialize the base Spark job.

        Args:
            job_name: Name of the specific job for logging purposes
        """
        self.job_name = job_name

        # Configure logging for Databricks environment

        logging.getLogger("py4j").setLevel(logging.ERROR)
        self.logger = QuintoAndarLogger(self.job_name)

        self.config_service = None

    def parse_args(self) -> Any:
        """Parse command line arguments."""
        parser = ArgumentParser(description=self.job_name)
        parser.add_argument("environment", type=str, help="Environment: forno/prod")
        parser.add_argument("bucket", type=str, help="S3 bucket name")
        parser.add_argument(
            "dag_name", type=str, help="DAG name without bietlejuice prefix"
        )
        parser.add_argument("schema", type=str, help="Database base name")
        parser.add_argument("table_name", type=str, help="Table name")
        parser.add_argument("load_start_date", type=str, help="Load start date")
        parser.add_argument("load_end_date", type=str, help="Load end date")
        parser.add_argument(
            "--extra_spark_job_arguments",
            type=str,
            default="{}",
            help="Extra spark job arguments (optional, defaults to empty JSON object)",
        )
        parser.add_argument(
            "--table_privileges",
            type=str,
            help="Table privileges as JSON string",
            default=None,
        )
        return parser.parse_args()

    def initialize_configuration(self, source: str) -> None:
        """
        Initialize configuration service.

        Args:
            source: Configuration source (typically dag_name)
        """
        self.config_service = ConfigurationService(source)
        self.logger.info(
            f"m=initialize_configuration, msg=Configuration initialized for source: {source}"
        )

    def get_config(self, key: str, required: bool = True, default: Any = None) -> Any:
        """
        Get configuration value.

        Args:
            key: Configuration key
            required: Whether the config is required
            default: Default value if not required and not found

        Returns:
            Configuration value

        Raises:
            ValueError: If required config is not found
        """
        try:
            value = self.config_service.get_config(key)
            if value is None and required:
                raise ValueError(f"{key} config is required but not found.")
            return value if value is not None else default
        except Exception as e:
            if required:
                self.logger.error(
                    f"m=get_config, msg=Required config {key} not found: {e}"
                )
                raise ValueError(f"{key} config is required but not found.")
            else:
                self.logger.warning(
                    f"m=get_config, msg=Optional config {key} not found: {e}"
                )
                return default

    def initialize_spark_session(self) -> SparkSession:
        """
        Initialize and return a Spark session with Delta Lake and S3 support.
        JARs are now installed in the default Spark JARs directory.

        Returns:
            Initialized SparkSession
        """
        self.logger.info(
            "m=initialize_spark_session, msg=Initializing Spark session with Delta Lake and S3 support"
        )

        try:
            spark = (
                SparkSession.builder.appName(self.job_name)
                .config(
                    "spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension"
                )
                .config(
                    "spark.sql.catalog.spark_catalog",
                    "org.apache.spark.sql.delta.catalog.DeltaCatalog",
                )
                .config(
                    "spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem"
                )
                .config(
                    "spark.hadoop.fs.s3a.aws.credentials.provider",
                    "com.amazonaws.auth.DefaultAWSCredentialsProviderChain",
                )
                .config("spark.hadoop.fs.s3a.path.style.access", "true")
                .config("spark.hadoop.fs.s3a.connection.maximum", "480")
                .config("spark.hadoop.fs.s3a.threads.max", "20")
                .config("spark.hadoop.fs.s3a.connection.timeout", "20000")
                .config("spark.hadoop.fs.s3a.socket.timeout", "20000")
                .getOrCreate()
            )

            self.logger.info(
                "m=initialize_spark_session, msg=Spark session initialized with Delta Lake and S3 support"
            )
            return spark

        except Exception as e:
            self.logger.warning(
                f"m=initialize_spark_session, msg=Failed to initialize with Delta Lake and S3 support: {e}"
            )
            self.logger.info(
                "m=initialize_spark_session, msg=Falling back to basic Spark session"
            )

            # Fall back to basic Spark session
            return SparkSession.builder.appName(self.job_name).getOrCreate()

    def setup_table_privileges(self, args: Any) -> TablePrivileges:
        """
        Setup table privileges from arguments.

        Args:
            args: Parsed command line arguments

        Returns:
            TablePrivileges instance
        """
        if args.table_privileges is not None:
            table_privileges_dict = json.loads(args.table_privileges)
            return TablePrivileges.from_input_dict(
                table_privileges_dict, f"{args.schema}.{args.table_name}"
            )
        else:
            return TablePrivileges.from_environment_default(
                f"{args.schema}.{args.table_name}"
            )

    @abstractmethod
    def create_core_model(self, spark: SparkSession, args: Any) -> DataFrame:
        """
        Abstract method to create the core model DataFrame.
        This method must be implemented by each specific core model job.

        Args:
            spark: SparkSession instance
            args: Parsed command line arguments

        Returns:
            DataFrame with the core model data
        """
        pass

    def run_pipeline(
        self, dataframe: DataFrame, args: Any, spark: SparkSession
    ) -> None:
        """
        Run the data loading pipeline.

        Args:
            dataframe: Core model DataFrame to load
            args: Parsed command line arguments
            spark: SparkSession instance
        """

        """ Make the default behaviour never update not null columns in target table with null values from source dataframe
            It is a requirement for core models, since we represent one entity per row and event based data not always have all columns filled
        """
        source_cols = dataframe.columns

        # Get target table columns if table exists, otherwise assume all columns are new
        target_table_name = f"{args.schema}.{args.table_name}"
        try:
            target_table = spark.table(target_table_name)
            target_cols = set(target_table.columns)
        except Exception:
            # Table doesn't exist yet, so all columns are new
            target_cols = set()

        # Create smart when_matched_operation:
        # - For existing columns (in both source and target): use CASE WHEN to preserve non-null target values
        # - For new columns (only in source): use source value directly
        default_when_matched_operation = {}
        for col in source_cols:
            if col in target_cols:
                # Existing column: preserve non-null target values
                default_when_matched_operation[
                    col
                ] = f"CASE WHEN source.{col} IS NOT NULL THEN source.{col} ELSE target.{col} END"
            else:
                # New column: use source value directly (target column doesn't exist yet)
                default_when_matched_operation[col] = f"source.{col}"

        # Get pipeline configuration
        merge_on = self.get_config("merge_on", required=False, default=None)

        when_matched_update_condition = self.get_config(
            "when_matched_update_condition", required=False, default=None
        )
        when_not_matched_insert_condition = self.get_config(
            "when_not_matched_insert_condition", required=False, default=None
        )
        when_matched_delete_condition = self.get_config(
            "when_matched_delete_condition", required=False, default=None
        )
        when_matched_operation = self.get_config(
            "when_matched_operation",
            required=False,
            default=default_when_matched_operation,
        )
        when_not_matched_operation = self.get_config(
            "when_not_matched_operation", required=False, default=None
        )
        partitions = self.get_config("partitions", required=False, default=None)

        # Setup table privileges
        table_privileges = self.setup_table_privileges(args)

        # Setup database location
        database_location = f"s3a://{args.bucket}/{LayerEnum.CORE.value}/{args.schema}/"

        self.logger.info(
            f"m=run_pipeline, msg=Loading data using DataFrameDeltaTableLoaderPipeline"
        )
        pipeline = DataFrameDeltaTableLoaderPipeline(
            database_name=args.schema,
            table_name=args.table_name,
            database_location=database_location,
            layer=LayerEnum.CORE.value,
            dataframe=dataframe,
            partitions=partitions,
            target_database_name=args.schema,
            target_database_location=database_location,
            merge_on=merge_on,
            when_matched_update_condition=when_matched_update_condition,
            when_not_matched_insert_condition=when_not_matched_insert_condition,
            when_matched_delete_condition=when_matched_delete_condition,
            when_matched_operation=when_matched_operation,
            when_not_matched_operation=when_not_matched_operation,
            table_privileges=table_privileges,
            spark=spark,
        )

        pipeline.run()
        self.logger.info("m=run_pipeline, msg=Data loading completed successfully")

    def run(self) -> None:
        """Main execution method."""
        args = self.parse_args()

        self.logger.info(f"m=run, msg=Starting {self.job_name} processing")
        self.logger.info(
            f"m=run, environment={args.environment}, bucket={args.bucket}, table={args.table_name}"
        )

        # Initialize configuration
        self.initialize_configuration(args.dag_name)

        # Initialize Spark session
        spark_session = self.initialize_spark_session()

        try:
            # Create core model (implemented by subclass)
            self.logger.info(f"m=run, msg=Creating {self.job_name} core model")
            core_model_df = self.create_core_model(spark_session, args)

            # Run the pipeline
            self.run_pipeline(core_model_df, args, spark_session)

            self.logger.info(
                f"m=run, msg={self.job_name} processing completed successfully"
            )

        except Exception as e:
            self.logger.error(f"m=run, msg=Error processing {self.job_name}: {str(e)}")
            raise
