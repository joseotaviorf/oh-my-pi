from typing import Dict, Union, List

import json
import ast
import logging
import yaml
import boto3

from datetime import datetime
from argparse import ArgumentParser
from pyspark.sql import Row
from pyspark.sql.dataframe import DataFrame
from quintoandar_logger import QuintoAndarLogger
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkDataFrameService, SparkTableStorageFormat
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader

from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.configuration_service import ConfigurationService

JOB_NAME = "load_lineage_and_tags_to_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def get_lineage_and_tags_data(
    s3_client, bucket: str, remote_path: str
) -> List[Dict[str, Union[str, bool]]]:
    obj = s3_client.get_object(
        Bucket=bucket, Key=f"{remote_path}metadata/all_lineage_tags_data.yml"
    )
    yaml_data = yaml.safe_load(obj["Body"])
    return yaml_data


def get_lineage_and_tags_df(spark_client: SparkClient, yaml_data: List) -> DataFrame:
    metadata_df = spark_client.create_dataframe(Row(**row) for row in yaml_data).drop(
        "columns"
    )
    return metadata_df


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str)
    parser.add_argument("datalake_bucket", type=str)
    parser.add_argument("source", type=str)
    parser.add_argument("table_name", type=str)
    parser.add_argument("execution_date_str", type=str)
    parser.add_argument("partitions", type=str)
    parser.add_argument("lineage_from_product_source_skip_list", type=str)
    parser.add_argument("dag_manual_mapping", type=str)

    args = parser.parse_args()
    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    execution_date_str = args.execution_date_str
    execution_date = datetime.strptime(execution_date_str, "%Y-%m-%d")
    partition_cols = ast.literal_eval(args.partitions)
    lineage_from_product_source_skip_list = set(ast.literal_eval(args.lineage_from_product_source_skip_list))
    dag_manual_mapping = json.loads(args.dag_manual_mapping)

    logger.info(
        f"""m={JOB_NAME}, env={env}, datalake_bucket={datalake_bucket}, source={source},
        table_name={table_name}, execution_date_str={execution_date_str}
        msg=Job execution started."""
    )

    config_service = ConfigurationService(source)
    databricks_bucket = config_service.get_config("databricks_bucket")
    dags_packages_files_path_in_s3 = config_service.get_config(
        "dags_packages_files_path_in_s3"
    )

    s3_loader = S3Loader()
    s3_client = boto3.client("s3")
    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    datalake_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)

    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = datalake_info["db_raw_path"]
    database_name = datalake_info["db_raw_databricks"]
    spark_metastore_service.create_database(database_name)

    # Creating metrics dataframe
    lineage_and_tags_yaml_data = get_lineage_and_tags_data(
        s3_client=s3_client,
        bucket=databricks_bucket,
        remote_path=dags_packages_files_path_in_s3,
    )
    lineage_and_tags_df = get_lineage_and_tags_df(
        spark_client=spark_client, yaml_data=lineage_and_tags_yaml_data
    )
    lineage_and_tags_df = (
        SparkDataFrameService()
        .input(lineage_and_tags_df)
        .create_year_month_day_columns_from_date(execution_date)
        .optimize_partitions_by_partition_columns(partition_cols)
        .output()
    )

    # loaders
    s3_loader.load_df(
        df=lineage_and_tags_df,
        s3_path=f"{database_location}{table_name}",
        format_options=format_options,
        partitions=partition_cols,
    )
    spark_metastore_loader.update_metastore(
        lineage_and_tags_df,
        database_name,
        table_name,
        format_options,
        database_location,
        partition_cols,
    )
    spark_metastore_service.create_new_partitions_from_df(
        database_name=database_name,
        table_name=table_name,
        df=lineage_and_tags_df,
        partition_cols=partition_cols,
    )
    spark_metastore_service.refresh_table(database_name, table_name)
