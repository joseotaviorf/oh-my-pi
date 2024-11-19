from argparse import ArgumentParser
from dateutil import parser

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.base.db.datalake_metastore_service import DatalakeMetastoreService
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.pipeline.full_table_loader_pipeline import FullTableLoaderPipeline
from pyspark.sql.functions import (
    concat_ws, col, from_json, explode, input_file_name, collect_list
)
from pyspark.sql.types import StructType, StructField, StringType, ArrayType, MapType
from bietlejuice.services.configuration_service import ConfigurationService
import yaml
import json
from bietlejuice.base.spark import (
    spark
)

JOB_NAME = "openapi_load"
logger = QuintoAndarLogger(JOB_NAME)
paths_schema = MapType(
    StringType(),
    MapType(
        StringType(),
        StructType([
            StructField("operationId", StringType(), True),
            StructField("description", StringType(), True),
            StructField("summary", StringType(), True),
            StructField("security", ArrayType(MapType(StringType(), ArrayType(StringType()))), True)
        ])
    )
)

def parse_yaml_safely(yaml_content):
    try:
        return json.dumps(yaml.safe_load(yaml_content), indent=2)
    except Exception as e:
        return None

def parse(df):
    """
    Parse yaml
    """

    # Group the content by file_path to handle multi-line YAML files
    grouped_data = df.groupBy("file_path").agg(
        concat_ws("\n", collect_list("value")).alias("yaml_content")
    )

    # Register the UDF
    parse_yaml_udf = udf(parse_yaml_safely, StringType())

    # Process each file
    processed_df = grouped_data.select(
        col("file_path"),
        parse_yaml_udf("yaml_content").alias("json_string")
    ).filter(col("json_string").isNotNull())

    # Parse JSON strings into structured columns, focusing on paths
    parsed_df = processed_df.select(
        col("file_path"),
        from_json(
            col("json_string"),
            StructType([
                StructField("paths", paths_schema, True)
            ])
        ).alias("json_data")
    )

    # Extract paths 
    paths_df = parsed_df.select(
        col("file_path"),
        explode(col("json_data.paths")).alias("path", "path_details")
    )

    # Extract HTTP methods
    methods_df = paths_df.select(
        col("file_path"),
        col("path"),
        explode(col("path_details")).alias("method", "operation_details")
    )

    result_df = methods_df.select(
        col("file_path"),
        col("path"),
        col("method"),
        col("operation_details.operationId").alias("operationId"),
        col("operation_details.description").alias("operation_description"),
        col("operation_details.security").alias("security"),
    )

    return result_df


def parse_arguments():
    arg_parser = ArgumentParser(description=JOB_NAME)
    arg_parser.add_argument("source")
    arg_parser.add_argument("env")
    arg_parser.add_argument("datalake_bucket")
    arg_parser.add_argument("schema")
    arg_parser.add_argument("execution_date")
    arg_parser.add_argument("table_name")
    args = arg_parser.parse_args()

    args.execution_date = parser.parse(args.execution_date)

    config_service = ConfigurationService(args.source)
    args.path = config_service.get_config("path")

    return args

def main():
    """
    This DAG loads openapi definitions.
    """
    args = parse_arguments()
    logger.info(
        f"""
        m=__main__, environment={args.env}, dag_name={JOB_NAME}
        datalake_bucket={args.datalake_bucket}, execution_date={args.execution_date},
        schema={args.schema}, table_name={args.table_name},
        msg=Starting spark job...
        """
    )

    raw_data = spark.read.format("text").load(args.path).withColumn("file_path", input_file_name())
    df = parse(raw_data)

    db_info = DatalakeMetastoreService.get_db_info(args.env, args.schema, args.datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    FullTableLoaderPipeline(
        database_name, args.table_name, database_location, LayerEnum.RAW, None
    ).load_and_register(df, format_options)

if __name__ == "__main__":
    main()