import logging
import ast
from argparse import ArgumentParser
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.base.spark import (
    SparkTableStorageFormat,
    SparkDataFrameService,
)
from bietlejuice.base.spark import spark
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.pipeline import IncrementalTableLoaderPipeline, FullTableLoaderPipeline
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline import LayerEnum

JOB_NAME = "Hightouch Logs Load"
spark_client = SparkClient()



def read_input(input_path, format, **params):
    """
    Read input data from either S3 path or catalog table.

    Args:
        input_path (str): S3 path or catalog table name
        format (str): Format type ('delta', 'parquet', 'table')

    Returns:
        DataFrame: Spark DataFrame with the loaded data
    """
    if format.lower() == 'table':
        # Read from catalog table
        logging.info(f"Reading from catalog table: {input_path}")
        df = spark.table(input_path)
    else:
        # Read from S3 path
        logging.info(f"Reading from S3 path: {input_path} with format: {format}")
        df = spark.read.format(format).load(input_path)

    return df

def load_table_into_datalake(df, table_name, environment, source, datalake_bucket, **params):
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
        db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
        database_name = db_info["db_raw_databricks"]
        database_location = db_info["db_raw_path"]
        format_options = SparkTableStorageFormat.DEFAULT_RAW

        spark_metastore_service = SparkMetastoreService(spark_client)

        logging.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
        spark_metastore_service.create_database(database_name)

        FullTableLoaderPipeline(
            database_name, table_name, database_location, LayerEnum.RAW, None
        ).load_and_register(df, format_options)
        # Initialize S3Loader


        logging.info(f"Successfully wrote DataFrame using S3Loader")
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

    parser.add_argument("environment",
                       help="Target environment")
    parser.add_argument("datalake_bucket",
                       help="Data lake S3 bucket")
    parser.add_argument("schema",
                       help="Database schema name")
    parser.add_argument("source",
                       help="Source name")
    parser.add_argument("table_name",
                       help="Table name")
    parser.add_argument("input_path",
                       help="Input path")
    parser.add_argument("format",
                       help="Input format")



    return parser.parse_args()

def main():

    # Configure logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )

    args = parse_arguments()

    params = {
        "environment": args.environment,                    # Target environment
        "datalake_bucket": args.datalake_bucket,          # Data lake S3 bucket"
        "schema": args.schema,                             # Database schema name
        "source": args.source,                             # Source name
        "table_name": args.table_name,                    # Table name
        "input_path": args.input_path.format(environment=args.environment),          # Input path
        "format": args.format          # Input path

    }
    logging.info(
        f"""
        m=__main__, environment={args.environment}, dag_name={JOB_NAME}
        datalake_bucket={args.datalake_bucket}, schema={args.schema}, table_name={args.table_name}, input_path={args.input_path}, format={args.format},
        msg=Starting spark job...
        """
    )
    df = read_input(**params)
    load_table_into_datalake(df, **params)

if __name__ == "__main__":
    main()
