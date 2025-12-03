import logging
import ast
from abc import ABC, abstractmethod
from argparse import ArgumentParser
from typing import Any
from quintoandar_logger import QuintoAndarLogger

from pyspark.sql import SparkSession, DataFrame

from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.core_models.helpers.schema_validator import (
    SchemaValidator,
    SchemaValidationError,
)
from bietlejuice.pipeline.dataframe_delta_table_loader_pipeline import (
    DataFrameDeltaTableLoaderPipeline,
)
from bietlejuice.services.configuration_service import ConfigurationService

from bietlejuice.base.notification.gchat_webhooks_enum import GchatWebhooksEnum
from bietlejuice.services.messaging_services.gchat_service import GChatService
from bietlejuice.services.messaging_services.message import Message
from bietlejuice.base.spark.base_spark import BaseDBUtils


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
        parser.add_argument(
            "partitions", help="Table partitions", nargs="?", default=None
        )
        parser.add_argument(
            "load_start_date", type=str, help="Load start date", nargs="?", default=None
        )
        parser.add_argument(
            "load_end_date", type=str, help="Load end date", nargs="?", default=None
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
        return TablePrivileges.from_environment_default(
            f"{args.schema}.{args.table_name}"
        )

    def get_expected_schema(self, args: Any) -> dict:
        """
        Get expected schema definition for DataFrame validation.

        First tries to load schema from S3 YAML file, then falls back to configuration.
        Schema file should be stored in S3 following the pattern:
        schemas/{table_name}.yml

        Expected schema format:
        {
            "columns": {
                "column_name": {
                    "type": "string|int|double|boolean|timestamp|date|...",
                    "nullable": True/False,
                    "required": True/False
                },
                ...
            },
            "strict": True/False,
            "min_columns": int,
            "max_columns": int
        }

        Args:
            args: Parsed command line arguments containing dag_name and table_name

        Returns:
            Schema definition dictionary
        """
        try:
            # First, try to load schema from S3 file
            schema_from_file = self._load_schema_from_s3_file(
                args.dag_name, args.table_name, args
            )
            if schema_from_file:
                self.logger.info(
                    f"m=get_expected_schema, msg=Using schema file from S3 for table {args.table_name}"
                )
                return schema_from_file
        except Exception as e:
            self.logger.warning(
                f"m=get_expected_schema, msg=Error loading schema file from S3: {e}, trying configuration"
            )

        try:
            # Fall back to configuration-based schema
            expected_schema = self.get_config(
                "expected_schema", required=False, default={}
            )
            if expected_schema:
                self.logger.info(
                    "m=get_expected_schema, msg=Using configured schema validation"
                )
                return expected_schema
            else:
                self.logger.info(
                    "m=get_expected_schema, msg=No schema validation configured"
                )
                return {}
        except Exception as e:
            self.logger.warning(
                f"m=get_expected_schema, msg=Error loading schema configuration: {e}, skipping validation"
            )
            return {}

    def _load_schema_from_s3_file(
        self, dag_name: str, table_name: str, args: Any
    ) -> dict:
        """
        Load schema definition from S3 YAML file.

        Schema file should be stored as: schemas/{dag_name}/{layer}/{table_name}.yml
        where layer is inferred from the schema argument (e.g., 'core' for core_visit)

        Args:
            dag_name: DAG name without bietlejuice prefix
            table_name: Table name
            args: Parsed command line arguments containing schema information

        Returns:
            Schema definition dictionary or empty dict if not found
        """
        try:
            from bietlejuice.base.service.dag_packages_path_service import (
                DAGPackagesPathService,
            )
            import yaml

            # Get the layer from the schema argument (e.g., 'core' from 'core_visit')
            # The schema argument typically follows the pattern: {layer}_{context}
            layer = args.schema.split("_")[0] if args.schema else "core"

            # Build the schema file path following the S3 structure: schemas/{dag_name}/{layer}/{table_name}.yml
            schema_file_relative_path = f"schemas/{dag_name}/{layer}/{table_name}.yml"

            self.logger.info(
                f"m=_load_schema_from_s3_file, msg=Attempting to load schema file: {schema_file_relative_path}"
            )

            # Use the same mechanism as query files to load from S3
            schema_content = DAGPackagesPathService._read_dag_package_file_from_s3(
                sql_file_relative_path=schema_file_relative_path
            )

            if schema_content:
                schema_dict = yaml.safe_load(schema_content)
                self.logger.info(
                    f"m=_load_schema_from_s3_file, msg=Successfully loaded schema file: {schema_file_relative_path}"
                )
                return schema_dict or {}
            else:
                self.logger.info(
                    f"m=_load_schema_from_s3_file, msg=Schema file is empty: {schema_file_relative_path}"
                )
                return {}

        except FileNotFoundError:
            self.logger.info(
                f"m=_load_schema_from_s3_file, msg=Schema file not found: {schema_file_relative_path}"
            )
            return {}
        except yaml.YAMLError as e:
            self.logger.error(
                f"m=_load_schema_from_s3_file, msg=Invalid YAML in schema file {schema_file_relative_path}: {e}"
            )
            raise ValueError(f"Invalid YAML in schema file: {e}")
        except Exception as e:
            self.logger.error(
                f"m=_load_schema_from_s3_file, msg=Unexpected error loading schema file: {e}"
            )
            raise

    def validate_dataframe_schema(self, dataframe: DataFrame, args: Any) -> None:
        """
        Validate DataFrame schema against expected schema definition.

        Args:
            dataframe: DataFrame to validate
            args: Parsed command line arguments

        Raises:
            SchemaValidationError: If validation fails and fail_on_schema_validation_error is True
        """
        expected_schema = self.get_expected_schema(args)

        if not expected_schema:
            self.logger.info(
                "m=validate_dataframe_schema, msg=No expected schema defined, skipping validation"
            )
            return

        try:
            validator = SchemaValidator()

            self.logger.info(
                f"m=validate_dataframe_schema, msg=Validating DataFrame schema for table {args.schema}.{args.table_name}"
            )

            # Log current DataFrame schema for debugging
            schema_summary = validator.get_schema_summary(dataframe)
            self.logger.info(
                f"m=validate_dataframe_schema, msg=Current DataFrame schema summary: {schema_summary}"
            )

            # Perform validation
            validator.validate_schema(dataframe, expected_schema)

            self.logger.info(
                f"m=validate_dataframe_schema, msg=Schema validation passed for table {args.schema}.{args.table_name}"
            )

        except SchemaValidationError as e:
            # Create detailed validation message
            detailed_error_msg = self._create_schema_validation_message(
                table_name=f"{args.schema}.{args.table_name}",
                schema_errors=str(e).split("\n"),
                expected_schema=expected_schema,
                actual_schema_summary=schema_summary,
            )

            self.logger.error(f"m=validate_dataframe_schema, msg={detailed_error_msg}")

            # Send webhook notification
            self._send_schema_validation_webhook(
                table_name=f"{args.schema}.{args.table_name}",
                validation_message=detailed_error_msg,
            )

            # Check if validation failures should stop execution
            fail_on_validation_error = self.get_config(
                "fail_on_schema_validation_error", required=False, default=True
            )

            if fail_on_validation_error:
                raise SchemaValidationError(detailed_error_msg)
            else:
                self.logger.warning(
                    "m=validate_dataframe_schema, msg=Schema validation failed but continuing execution due to configuration"
                )

        except Exception as e:
            self.logger.error(
                f"m=validate_dataframe_schema, msg=Unexpected error during schema validation: {str(e)}"
            )
            # For unexpected errors, we should probably fail unless explicitly configured not to
            fail_on_validation_error = self.get_config(
                "fail_on_schema_validation_error", required=False, default=True
            )

            if fail_on_validation_error:
                raise
            else:
                self.logger.warning(
                    "m=validate_dataframe_schema, msg=Schema validation error but continuing execution due to configuration"
                )

    def _create_schema_validation_message(
        self,
        table_name: str,
        schema_errors: list,
        expected_schema: dict,
        actual_schema_summary: dict,
    ) -> str:
        """
        Create a detailed schema validation message similar to CDC schema changes notifier.

        Args:
            table_name: Name of the table being validated
            schema_errors: List of validation errors from SchemaValidator
            expected_schema: Expected schema definition
            actual_schema_summary: Actual DataFrame schema summary

        Returns:
            Formatted validation message
        """
        message = f"Schema validation failed for table {table_name}.\n\n"

        if schema_errors:
            message += "Validation Errors:\n"
            for error in schema_errors:
                message += f"• {error}\n"
            message += "\n"

        if expected_schema and "columns" in expected_schema:
            message += "Expected Schema:\n"
            for col_name, col_def in expected_schema["columns"].items():
                nullable = (
                    "nullable" if col_def.get("nullable", True) else "non-nullable"
                )
                required = "required" if col_def.get("required", True) else "optional"
                message += f"• {col_name}: {col_def.get('type', 'unknown')} ({nullable}, {required})\n"
            message += "\n"

        if actual_schema_summary and "columns" in actual_schema_summary:
            message += "Actual Schema:\n"
            for col_name, col_info in actual_schema_summary["columns"].items():
                nullable = (
                    "nullable" if col_info.get("nullable", True) else "non-nullable"
                )
                message += (
                    f"• {col_name}: {col_info.get('type', 'unknown')} ({nullable})\n"
                )

        return message.rstrip()

    def _send_schema_validation_webhook(
        self, table_name: str, validation_message: str
    ) -> None:
        """
        Send schema validation failure notification via webhook.

        Args:
            table_name: Name of the table that failed validation
            validation_message: Detailed validation message
        """
        try:
            # Get webhook URL from dbutils secrets
            try:
                base_dbutils = BaseDBUtils()
                dbutils = base_dbutils.get_dbutils()
                webhook_url = dbutils.secrets.get(
                    scope="quintoandar",
                    key=GchatWebhooksEnum.GCHAT_CORE_MODEL_SCHEMA_VALIDATION,
                )
            except Exception as e:
                self.logger.warning(
                    f"m=_send_schema_validation_webhook, msg=Failed to get webhook from dbutils: {str(e)}"
                )
                webhook_url = None

            if webhook_url:
                # Create message object
                message = Message(validation_message, webhook_url)

                # Send notification
                GChatService.send_message(message)

                self.logger.info(
                    f"m=_send_schema_validation_webhook, msg=Schema validation webhook sent for table {table_name}"
                )
            else:
                self.logger.info(
                    "m=_send_schema_validation_webhook, msg=No CORE_MODEL_WEBHOOK secret found in dbutils for schema validation notifications"
                )

        except Exception as e:
            self.logger.warning(
                f"m=_send_schema_validation_webhook, msg=Failed to send schema validation webhook: {str(e)}"
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
        if args.partitions is not None:
            partitions = ast.literal_eval(args.partitions)
        else:
            partitions = []
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
                default_when_matched_operation[col] = (
                    f"CASE WHEN source.{col} IS NOT NULL THEN source.{col} ELSE target.{col} END"
                )
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

        # Setup table privileges
        table_privileges = self.setup_table_privileges(args)

        # Setup database location
        database_location = f"s3a://{args.bucket}/{LayerEnum.CORE.value}/{args.schema}/"

        self.logger.info(
            f"m=run_pipeline, msg=Loading data using DataFrameDeltaTableLoaderPipeline with partitions: {partitions}"
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

            # Validate DataFrame schema before writing
            self.logger.info(f"m=run, msg=Validating {self.job_name} core model schema")
            self.validate_dataframe_schema(core_model_df, args)

            # Run the pipeline
            self.run_pipeline(core_model_df, args, spark_session)

            self.logger.info(
                f"m=run, msg={self.job_name} processing completed successfully"
            )

        except Exception as e:
            self.logger.error(f"m=run, msg=Error processing {self.job_name}: {str(e)}")
            raise
