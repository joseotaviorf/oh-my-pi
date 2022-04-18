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

from bietlejuice.jobs.composer.services.dag_metadata_service import DAGMetadataService
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


def get_dag_metadata(
    lineage_from_product_skip_list: Set[str], dag_manual_mapping: Dict, environment: str
) -> List[Dict[str, str]]:
    dags = []
    metadata_service = DAGMetadataService(dag_manual_mapping)
    for file in FileService.list_dag_files():
        source, context, dag = metadata_service.get_dag_info_from_path(file)
        if source not in lineage_from_product_skip_list:
            layers = metadata_service.get_dag_layers(source, context, dag)
            for layer in layers:
                dags.append(
                    {
                        "database": metadata_service.get_dag_database_name(
                            source, context, dag, layer
                        ),
                        "has_lineage_from_product": metadata_service.dag_has_lineage_from_product_config(
                            source, context, dag, environment
                        ),
                        "owner": metadata_service.get_dag_owner(source, context, dag),
                    }
                )
    return dags


def get_dag_metadata_df(
    spark_client: SparkClient,
    lineage_from_product_skip_list: Set[str],
    dag_manual_mapping: Dict,
    env: str,
) -> DataFrame:
    dag_metadata_data = get_dag_metadata(
        lineage_from_product_skip_list, dag_manual_mapping, env
    )
    metadata_df = spark_client.create_dataframe(
        Row(**row) for row in dag_metadata_data
    ).drop("columns")
    return metadata_df


# ################################  Comparison  ##################################


def compare_metadata_with_metastore(
    metadata_data, metastore_data, dag_metadata, spark_client
):
    metadata_data.createOrReplaceTempView("vw_metadata")
    metastore_data.createOrReplaceTempView("vw_metastore")
    dag_metadata.createOrReplaceTempView("vw_dag_info")

    query = f"""
      WITH aggregated_dag_info as (
      SELECT
        database,
        collect_set(owner) as owners,
        collect_set(has_lineage_from_product) as has_lineage_from_product
      FROM
        vw_dag_info as di
      GROUP BY
        database
    ),
    dag_info as (
      SELECT
        database,
        array_join(owners, ", ") as owners,
        CASE
          WHEN size(has_lineage_from_product) > 1 THEN null
          ELSE has_lineage_from_product[0]
        END as has_lineage_from_product
      FROM
        aggregated_dag_info as adi
    )
    SELECT
        ms.layer,
        ms.database_name,
        ms.table_name,
        di.owners,
        COALESCE(md.has_lineage, di.has_lineage_from_product, False) as has_lineage,
        COALESCE(md.has_tags, False) as has_tags
    FROM
        vw_metastore AS ms
    LEFT JOIN
        vw_metadata AS md
            ON ms.database_name = md.database_name
            AND ms.table_name = md.table_name
    LEFT JOIN
        dag_info as di
            ON ms.database_name = di.database
    """

    return spark_client.get_records(query)


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
    schemas_skip_list = config_service.get_config("DATABASE_SKIP_LIST")
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
    metastore_tables_df = get_tables_from_metastore(spark_client, schemas_skip_list)
    lineage_and_tags_df = get_lineage_and_tags_df(spark_client)
    dag_metadata_df = get_dag_metadata_df(
        spark_client, lineage_from_product_source_skip_list, dag_manual_mapping, env
    )
    lineage_and_tags_metrics_df = compare_metadata_with_metastore(
        lineage_and_tags_df, metastore_tables_df, dag_metadata_df, spark_client
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
