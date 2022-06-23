from typing import Dict, Union, List

import logging

import yaml

from datetime import datetime
from argparse import ArgumentParser
from pyspark.sql import Row
from pyspark.sql.dataframe import DataFrame
from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import (
    SparkDataFrameService,
    SparkTableStorageFormat,
)
from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader
from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader

from bietlejuice.jobs.composer.services import FileService

from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

JOB_NAME = "load_lineage_and_tags_to_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def get_first_key(input_dict: dict) -> str:
    """
    returns the first key of a dict
    it is expected that the key is a string
    """
    return next(iter(input_dict))


def get_lineage_and_tags_data() -> List[Dict[str, Union[str, bool]]]:
    yamls_data = []
    for file in FileService.list_metadata_files():
        with open(file, "r") as fp:
            data = yaml.safe_load(fp)
            db_name = data["database_name"]
            tb_name = data["table_name"]
            columns = data.get("columns")
            if not columns:
                file_type = "tags"
            else:
                first_column_key = get_first_key(columns)
                file_type = get_first_key(data["columns"][first_column_key])

        yamls_data.append(
            {
                "database_name": db_name,
                "table_name": tb_name,
                "has_lineage": file_type == "lineage",
                "has_tags": file_type == "tags",
            }
        )
    return yamls_data


def get_lineage_and_tags_df(spark_client: SparkClient) -> DataFrame:
    yaml_data = get_lineage_and_tags_data()
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

    args = parser.parse_args()
    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    execution_date_str = args.execution_date_str
    execution_date = datetime.strptime(execution_date_str, "%Y-%m-%d")

    logger.info(
        f"""m={JOB_NAME}, env={env}, datalake_bucket={datalake_bucket}, source={source},
        table_name={table_name}, execution_date_str={execution_date_str}
        msg=Job execution started."""
    )

    config_service = ConfigurationService(source)
    partition_cols = config_service.get_config("PARTITION_COLUMNS")
    lineage_from_product_source_skip_list = set(
        config_service.get_config("LINEAGE_FROM_PRODUCT_SOURCES_SKIP_LIST")
    )
    dag_manual_mapping = config_service.get_config("DAG_METADATA_MANUAL_MAPPING")

    s3_loader = S3Loader()
    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    datalake_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)

    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = datalake_info["db_raw_path"]
    database_name = datalake_info["db_raw_databricks"]
    spark_metastore_service.create_database(database_name)

    # Creating metrics dataframe
    lineage_and_tags_df = get_lineage_and_tags_df(spark_client)
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
