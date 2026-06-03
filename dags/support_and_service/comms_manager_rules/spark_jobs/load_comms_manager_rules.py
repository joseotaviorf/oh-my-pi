"""
Communications Manager Rules Data Loading Job

This Spark job loads communication manager rules from S3 by finding the most
recently updated version file and processing it for data pipeline consumption.

Author: Data Engineering Team
"""

import ast
import logging
from argparse import ArgumentParser

from pyspark.sql.functions import col, dayofmonth, explode, month, to_timestamp, year

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat, spark
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.loaders.s3_loader import S3Loader

# Job configuration
JOB_NAME = "Load Comms Manager Rules"


def collect_all_files(path, file_extension=".json"):
    """
    Recursively collect all files with specified extension from the given path and subdirectories.

    Args:
        path (str): S3 path to search for files
        file_extension (str): File extension to filter by (default: '.json')

    Returns:
        list: List of file objects matching the extension
    """
    dbutils = BaseDBUtils().get_dbutils()
    all_files = []

    try:
        items = dbutils.fs.ls(path)
        for item in items:
            if item.isDir():
                # If it's a directory, recursively search inside
                logging.debug(f"Exploring directory: {item.path}")
                all_files.extend(collect_all_files(item.path, file_extension))
            else:
                # If it's a file, check if it matches the extension
                if item.path.lower().endswith(file_extension.lower()):
                    all_files.append(item)
                    logging.debug(f"Found {file_extension} file: {item.path}")
                else:
                    logging.debug(f"Skipping non-{file_extension} file: {item.path}")
    except Exception as e:
        logging.warning(f"Could not access path {path}: {str(e)}")

    return all_files


def get_last_version(comms_manager_rules_path):
    """
    Retrieves the most recently modified JSON file from the communication manager rules S3 directory.

    This function recursively searches through folders to find JSON files, then returns the
    path of the file with the latest modification time. It handles nested folder structures
    like date-based partitioning (e.g., 2024/01/15/rules.json).

    Args:
        comms_manager_rules_path (str): S3 path to search for communication manager rules files

    Returns:
        str: S3 path to the most recently modified JSON file, or None if no files found

    Raises:
        Exception: If S3 access fails
    """
    try:
        # Collect all JSON files recursively
        logging.info(f"Searching for JSON files in: {comms_manager_rules_path}")
        all_json_files = collect_all_files(comms_manager_rules_path)

        # Check if any JSON files were found
        if not all_json_files:
            logging.warning(f"No JSON files found in path: {comms_manager_rules_path}")
            return None

        logging.info(f"Found {len(all_json_files)} JSON files")

        # Convert file metadata to Spark DataFrame for easier manipulation
        df = spark.createDataFrame(all_json_files)

        # Find the file with the most recent modification time
        # Sort by modification time in descending order and take the first record
        last_updated = (
            df.orderBy(
                col("modificationTime").desc()
            )  # Sort by modification time (newest first)
            .limit(1)  # Take only the most recent file
            .collect()[0]  # Collect and get the first (only) row
        )

        # Log the details of the most recently updated file using proper f-string formatting
        logging.info(f"Most recent JSON file: {last_updated.path}")
        logging.info(f"Modified at (ms): {last_updated.modificationTime}")
        logging.info(f"File size: {last_updated.size} bytes")

        return last_updated.path

    except Exception as e:
        logging.error(
            f"Failed to get last version from {comms_manager_rules_path}: {str(e)}"
        )
        raise


def read_communication_rules_json(file_path):
    """
    Reads communication manager rules JSON file from S3.

    Uses multiline option to properly parse complex JSON structures with nested arrays.

    Args:
        file_path (str): S3 path to the JSON file containing communication rules

    Returns:
        DataFrame: Raw Spark DataFrame with the JSON data

    Raises:
        Exception: If file reading fails
    """
    try:
        logging.info(f"Reading communication rules from: {file_path}")

        df = spark.read.option("multiline", "true").json(
            file_path
        )  # Enable multiline JSON parsing for complex structures

        logging.info(f"Successfully loaded JSON file with {df.count()} root records")
        return df

    except Exception as e:
        logging.error(f"Failed to read JSON file from {file_path}: {str(e)}")
        raise


def explode_rules(df):
    """
    Explodes the rules array from the root JSON structure.

    Takes the raw JSON DataFrame and extracts individual rules from the 'rules' array,
    creating one row per rule.

    Args:
        df (DataFrame): Raw DataFrame containing the rules JSON structure

    Returns:
        DataFrame: DataFrame with exploded rules, one row per rule
    """
    logging.info("Exploding rules array from JSON structure")

    rules_df = df.select(
        to_timestamp(col("metadata.generated_at")).alias("generated_at"),
        explode("rules").alias("rule"),
    )
    logging.info(f"Exploded to {rules_df.count()} individual rules")
    return rules_df


def explode_and_flatten_actions(rules_df):
    """
    Explodes actions within each rule and flattens the nested structure.

    Takes the rules DataFrame and:
    1. Extracts rule-level fields (id, status, scope)
    2. Explodes the actions array within each rule
    3. Flattens all nested fields into a single flat structure

    Args:
        rules_df (DataFrame): DataFrame with exploded rules

    Returns:
        DataFrame: Completely flattened DataFrame with one row per rule-action combination
    """
    logging.info("Exploding actions and flattening rule structure")

    # Step 1: Explode actions within each rule and extract rule-level fields
    # Using col() for all fields except IDs to handle optional fields gracefully
    rules_with_actions = rules_df.select(
        col("generated_at"),
        "rule.rule_id",  # ID fields use direct access
        col("rule.status").alias("status"),
        col("rule.scope.business_context").alias("business_context"),
        col("rule.scope.category").alias("category"),
        col("rule.scope.company").alias("company"),
        col("rule.scope.context").alias("context"),
        col("rule.scope.cost_center").alias("cost_center"),
        col("rule.scope.journey_step").alias("journey_step"),
        col("rule.scope.line").alias("line"),
        col("rule.scope.profile").alias("rule_profile"),
        col("rule.scope.team").alias("team"),
        explode("rule.actions").alias("action"),
    )

    # Step 2: Flatten all action fields into the final structure
    # Using col() for all fields except IDs to handle optional fields gracefully
    flat_df = rules_with_actions.select(
        # Rule-level fields
        col("generated_at"),
        "rule_id",  # ID fields use direct access
        col("status"),
        col("business_context"),
        col("category"),
        col("company"),
        col("context"),
        col("cost_center"),
        col("journey_step"),
        col("line"),
        col("rule_profile"),
        col("team"),
        # Action-level fields
        "action.action_id",  # ID fields use direct access
        col("action.notification_type").alias("notification_type"),
        col("action.profile").alias("action_profile"),
        col("action.reason").alias("reason"),
        col("action.deep_link").alias("deep_link"),
        # Template fields
        col("action.templates.subject_template").alias("subject_template"),
        col("action.templates.body_template").alias("body_template"),
        col("action.templates.body_template_path").alias("body_template_path"),
        col("action.templates.subject_content").alias("subject_content"),
        col("action.templates.body_content").alias("body_content"),
    )

    flat_df = flat_df.withColumn("year", year(col("generated_at")))
    flat_df = flat_df.withColumn("month", month(col("generated_at")))
    flat_df = flat_df.withColumn("day", dayofmonth(col("generated_at")))

    logging.info(f"Flattened to {flat_df.count()} rule-action combinations")
    return flat_df


def process_communication_rules(file_path):
    """
    # Complete pipeline to process communication manager rules from JSON to flattened DataFrame.

    This function orchestrates the entire transformation process:
    1. Reads the JSON file from S3
    2. Explodes the rules array
    3. Explodes actions and flattens the structure

    Args:
        file_path (str): S3 path to the communication rules JSON file

    Returns:
        DataFrame: Fully processed and flattened DataFrame ready for analysis

    Raises:
        # Exception: If any step in the processing pipeline fails
    """
    try:
        logging.info("Starting communication rules processing pipeline")

        # Step 1: Read the JSON file
        raw_df = read_communication_rules_json(file_path)

        # Step 2: Explode rules array
        rules_df = explode_rules(raw_df)

        # Step 3: Explode actions and flatten structure
        flat_df = explode_and_flatten_actions(rules_df)

        logging.info("Communication rules processing pipeline completed successfully")
        return flat_df

    except Exception as e:
        logging.error(f"Communication rules processing failed: {str(e)}")
        raise


def write_dataframe_with_s3_loader(df, s3_path, partitions=None):
    """
    Writes a DataFrame using S3Loader for raw layer data.

    Uses the bietlejuice S3Loader class with JSON format (DEFAULT_RAW) for raw layer ingestion,
    following the same pattern as other raw data jobs like amplitude_new.

    Args:
        df (DataFrame): Spark DataFrame to write
        s3_path (str): S3 path where data should be written
        partitions (str, optional): Partition specification from YAML, or None for no partitioning

    Raises:
        Exception: If writing fails
    """
    try:
        logging.info(f"Writing DataFrame using S3Loader to raw layer: {s3_path}")

        # Initialize S3Loader
        s3_loader = S3Loader()

        # Parse partition columns using ast.literal_eval (same as base_core_model_spark_job)
        partition_cols = None
        if partitions is not None:
            try:
                partition_cols = ast.literal_eval(partitions)
                if partition_cols:
                    logging.info(f"Using partitions: {partition_cols}")
                else:
                    partition_cols = None
                    logging.info(
                        "No valid partition columns found, writing without partitioning"
                    )
            except (ValueError, SyntaxError) as e:
                logging.warning(
                    f"Invalid partition format '{partitions}': {e}. Expected Python list format like ['year', 'month', 'day']"
                )
                partition_cols = None
                logging.info(
                    "Writing without partitioning due to invalid partition format"
                )
        else:
            logging.info("No partitions specified, writing without partitioning")

        # Load data using S3Loader with raw layer defaults (JSON format)
        s3_loader.load_df(
            df=df,
            s3_path=s3_path,
            format_options=SparkTableStorageFormat.DEFAULT_RAW,  # JSON format for raw layer
            partitions=partition_cols,
            optimize_dataframe=False,  # Same as amplitude job
        )

        logging.info("Successfully wrote DataFrame using S3Loader")
        logging.info(f"Total records written: {df.count()}")

    except Exception as e:
        logging.error(f"Failed to write DataFrame using S3Loader: {str(e)}")
        raise


def parse_arguments():
    """
    Parse command-line arguments for the Communication Manager Rules loading job.

    Returns:
        Namespace: Parsed arguments object with all required parameters
    """
    parser = ArgumentParser(description=JOB_NAME)

    # Define required command-line arguments in the exact order from declaration file
    parser.add_argument("environment", help="Target environment (e.g., prod, forno)")
    parser.add_argument("datalake_bucket", help="S3 bucket name for the data lake")
    parser.add_argument("dag_name", help="DAG name identifier")
    parser.add_argument("schema", help="Database schema name")
    parser.add_argument("table_name", help="Table name")
    parser.add_argument(
        "partitions", help="Partition information", nargs="?", default=None
    )
    parser.add_argument(
        "comms_manager_rules_path", help="S3 path for communication manager rules"
    )
    parser.add_argument("execution_date", help="Execution date in YYYY-MM-DD format")

    add_validation_target_args(parser)

    return parser.parse_args()


def main():
    """
    Main execution function for the Communication Manager Rules loading job.

    This function orchestrates the entire data loading process:
    1. Parses command-line arguments
    2. Configures logging
    3. Finds the latest rules file
    4. Processes the data
    5. Writes to S3 using S3Loader

    Raises:
        Exception: If any step in the process fails
    """
    # Parse command-line arguments
    args = parse_arguments()

    # Extract and assign parsed arguments to variables
    environment = args.environment  # Target environment
    datalake_bucket = args.datalake_bucket  # Data lake S3 bucket
    dag_name = args.dag_name  # DAG name identifier
    schema = args.schema  # Database schema name
    table_name = args.table_name  # Table name
    partitions = args.partitions  # Partition information
    execution_date = args.execution_date  # Job execution date

    # Format the S3 path with the environment parameter
    comms_manager_rules_path = args.comms_manager_rules_path.format(
        environment=environment
    )

    # Configure logging
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    )

    try:
        logging.info(f"Starting {JOB_NAME} for environment: {environment}")
        logging.info(f"Using rules path: {comms_manager_rules_path}")
        logging.info(f"Target datalake bucket: {datalake_bucket}")
        logging.info(f"DAG name: {dag_name}")
        logging.info(f"Schema: {schema}")
        logging.info(f"Table name: {table_name}")
        logging.info(f"Partitions: {partitions}")
        logging.info(f"Execution date: {execution_date}")

        # Find the most recent communication manager rules file
        latest_file_path = get_last_version(comms_manager_rules_path)

        if latest_file_path is None:
            logging.warning(
                "No files to process. Job completed without processing data."
            )
            logging.info(f"{JOB_NAME} completed successfully (no files to process)")
            return  # Return instead of exit(0) for better testability

        logging.info(f"Processing latest file: {latest_file_path}")

        # Process the communication rules using the modular pipeline
        processed_df = process_communication_rules(latest_file_path)

        db_info = DatalakeMetastoreService.get_db_info(
            environment, schema, datalake_bucket
        )
        write_database_name, write_table_name, write_location = (
            resolve_datalake_write_target(
                prod_database=db_info["db_raw_databricks"],
                prod_table=table_name,
                prod_location=db_info["db_raw_path"],
                bucket=datalake_bucket,
                target_database=args.target_database_name,
                target_table=args.target_table_name,
            )
        )
        logging.info(
            "Validation write target: %s.%s",
            write_database_name,
            write_table_name,
        )

        # Write the processed data using S3Loader (same pattern as amplitude_new)
        output_path = f"{write_location}{write_table_name}"
        write_dataframe_with_s3_loader(processed_df, output_path, partitions)

        # Show the schema for verification
        logging.info("Processed DataFrame schema:")
        processed_df.printSchema()

        logging.info(f"{JOB_NAME} completed successfully")

    except Exception as e:
        logging.error(f"Job failed with error: {str(e)}")
        raise


if __name__ == "__main__":
    """
    Entry point for the Communication Manager Rules loading job.

    This script is designed to be executed as a Spark job, typically called from
    an Airflow DAG or other orchestration system.

    Command-line Arguments:
        environment: Target environment (e.g., 'prod', 'dev', 'staging')
        datalake_bucket: S3 bucket name for the data lake
        dag_name: DAG name identifier
        schema: Database schema name
        table_name: Table name
        partitions: Partition information
        execution_date: Date of execution in YYYY-MM-DD format
        comms_manager_rules_path: S3 path template for communication manager rules

    Example Usage:
        python load_comms_manager_rules.py prod my-datalake-bucket comms-manager 2023-12-01
               "s3://comms-manager-{environment}/notification-rules/versions/"
    """
    main()
