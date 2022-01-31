import re
from typing import Dict, Union, List, Set

import logging

import yaml

from datetime import datetime
from argparse import ArgumentParser
from pyspark.sql import Row
from pyspark.sql.functions import udf
from pyspark.sql.types import StructType, StructField, StringType
from pyspark.sql.dataframe import DataFrame
from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.pipeline.layer_enum import LayerEnum
from bietlejuice.jobs.composer.base.spark import (
    SparkDataFrameService,
    SparkTableStorageFormat,
)
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader

from bietlejuice.jobs.composer.services import FileService
from bietlejuice.jobs.composer.services.metadata_service import MetadataService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

JOB_NAME = "load_lineage_and_tags_metrics_to_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


# ################################  Metastore Data  ##################################
# TODO: these functions could be in a common place instead of copy-pasted between the following jobs:
# - load_lineage_and_tags_metrics_to_raw
# - load_columns_documentation_metrics_to_raw
# - load_tables_documentation_metrics_to_raw


def get_tables_from_metastore(spark_client, schemas_skip_list):
    final_df = get_empty_df(spark_client)
    databases = list_metastore_databases(spark_client, schemas_skip_list)

    for database in databases:
        tables_df = (
            spark_client.get_records(f"SHOW TABLES IN {database}")
            .where("isTemporary = false")
            .drop("isTemporary")
        )
        final_df = final_df.union(tables_df)

    udf_extract_layer = udf(extract_layer_from_database_name)
    final_df = final_df.withColumn("layer", udf_extract_layer("database_name"))

    return final_df


def get_empty_df(spark_client):
    df_schema = StructType(
        [
            StructField("database_name", StringType(), True),
            StructField("table_name", StringType(), True),
        ]
    )
    return spark_client.create_dataframe([], df_schema)


def list_metastore_databases(spark_client, schemas_skip_list):
    databases_df = (
        spark_client.get_records("SHOW DATABASES")
        .where("databaseName not like '%_staging%'")
        .collect()
    )
    databases = [
        db.databaseName
        for db in databases_df
        if db.databaseName not in schemas_skip_list
    ]
    return databases


def extract_layer_from_database_name(database_name):
    if database_name.startswith("dw_"):
        return LayerEnum.DW.value
    elif database_name.startswith("datalake_"):
        if database_name.endswith("_raw"):
            return LayerEnum.RAW.value
        if database_name.endswith("_clean"):
            return LayerEnum.CLEAN.value
        else:
            return LayerEnum.ENRICH.value
    return ""


# ################################ Lineage and Tags Files data  ##################################


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


def should_skip_source(source, skip_list):
    if source in skip_list or source.startswith("dw_") or source.startswith("enrich_"):
        return True
    return False


def get_lineage_from_product_data(
    lineage_from_product_skip_list: Set[str], environment: str
) -> List[Dict[str, str]]:
    dags_data = []
    metadata_service = MetadataService()
    dag_regex = re.compile(
        r"dags/(?P<source>\w+)(?:/(?P<context>\w+))?/(?P<dag>\w+)\.py"
    )
    for file in FileService.list_dag_files():
        match = re.search(dag_regex, file).groupdict()
        dag = match["dag"]
        source = match["source"]
        context = match["context"]
        if (
            source
            and dag
            and not should_skip_source(source, lineage_from_product_skip_list)
        ):
            if context:
                source_with_context = f"source={source} context={context}"
                database_name = f"datalake_{source}_{context}_raw"
            else:
                context = source
                database_name = f"datalake_{source}_raw"
                source_with_context = f"source={source}"

            has_lineage_from_product = metadata_service.dag_has_lineage_from_product_config(
                source, context, dag, environment
            )
            logger.info(
                f"m=get_lineage_from_product_data, {source_with_context}, database_name={database_name}, "
                f"has_lineage_from_product={has_lineage_from_product} "
            )
            dags_data.append(
                {
                    "database_name": database_name,
                    "has_lineage_from_product": has_lineage_from_product,
                }
            )
    return dags_data


def get_lineage_from_product_df(
    spark_client: SparkClient, lineage_from_product_skip_list: Set[str], env: str
) -> DataFrame:
    lineage_from_product_data = get_lineage_from_product_data(
        lineage_from_product_skip_list, env
    )
    metadata_df = spark_client.create_dataframe(
        Row(**row) for row in lineage_from_product_data
    ).drop("columns")
    return metadata_df


# ################################  Comparison  ##################################


def compare_metadata_with_metastore(
    metadata_data, metastore_data, lineage_from_product_data, spark_client
):
    metadata_data.createOrReplaceTempView("vw_metadata")
    metastore_data.createOrReplaceTempView("vw_metastore")
    lineage_from_product_data.createOrReplaceTempView("vw_lineage_from_product")

    query = f"""
      SELECT
          ms.layer,
          ms.database_name,
          ms.table_name,
          COALESCE(md.has_lineage, lfp.has_lineage_from_product, False) as has_lineage,
          COALESCE(md.has_tags, False) as has_tags
      FROM
          vw_metastore AS ms
      LEFT JOIN
          vw_metadata AS md
              ON ms.database_name = md.database_name
              AND ms.table_name = md.table_name
      LEFT JOIN
          vw_lineage_from_product as lfp
              ON ms.database_name = lfp.database_name
    """

    return spark_client.get_records(query)


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name")
    parser.add_argument("execution_date_str")

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
    schemas_skip_list = config_service.get_config("DATABASE_SKIP_LIST")
    partition_cols = config_service.get_config("PARTITION_COLUMNS")
    lineage_from_product_source_skip_list = set(
        config_service.get_config("LINEAGE_FROM_PRODUCT_SOURCES_SKIP_LIST")
    )

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
    metastore_tables_df = get_tables_from_metastore(spark_client, schemas_skip_list)
    lineage_and_tags_df = get_lineage_and_tags_df(spark_client)
    lineage_from_product_df = get_lineage_from_product_df(
        spark_client, lineage_from_product_source_skip_list, env
    )
    lineage_and_tags_metrics_df = compare_metadata_with_metastore(
        lineage_and_tags_df, metastore_tables_df, lineage_from_product_df, spark_client
    )
    lineage_and_tags_metrics_df = (
        SparkDataFrameService()
        .input(lineage_and_tags_metrics_df)
        .create_year_month_day_columns_from_date(execution_date)
        .optimize_partitions_by_partition_columns(partition_cols)
        .output()
    )

    # loaders
    s3_loader.load_df(
        df=lineage_and_tags_metrics_df,
        s3_path=f"{database_location}{table_name}",
        format_options=format_options,
        partitions=partition_cols,
    )
    spark_metastore_loader.update_metastore(
        lineage_and_tags_metrics_df,
        database_name,
        table_name,
        format_options,
        database_location,
        partition_cols,
    )
    spark_metastore_service.create_new_partitions_from_df(
        database_name=database_name,
        table_name=table_name,
        df=lineage_and_tags_metrics_df,
        partition_cols=partition_cols,
    )
    spark_metastore_service.refresh_table(database_name, table_name)
