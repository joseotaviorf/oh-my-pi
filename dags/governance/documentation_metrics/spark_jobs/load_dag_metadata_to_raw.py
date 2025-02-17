from typing import Dict, List, Set

import json
import ast
import logging

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

from bietlejuice.services import FileService

from bietlejuice.services.dag_metadata_service import DAGMetadataService
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_dag_metadata_to_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def get_dag_metadata(
    lineage_from_product_skip_list: Set[str], dag_manual_mapping: Dict
) -> List[Dict[str, str]]:
    dags = []
    metadata_service = DAGMetadataService(dag_manual_mapping)
    for file in FileService.list_dag_files():
        source, context, dag = metadata_service.get_dag_info_from_path(file)
        if source not in lineage_from_product_skip_list:
            layers = metadata_service.get_dag_layers(dag)
            for layer in layers:
                dags.append(
                    {
                        "layer": layer,
                        "dag_name": f"bietlejuice.{dag}",
                        "database_name": metadata_service.get_dag_database_name(
                            dag, layer
                        ),
                        "has_lineage_from_product": metadata_service.dag_has_lineage_from_product_config(
                            source, context, dag
                        ),
                        "owner": metadata_service.get_dag_owner(dag),
                    }
                )
    return dags


def get_dag_metadata_df(
    spark_client: SparkClient,
    lineage_from_product_skip_list: Set[str],
    dag_manual_mapping: Dict,
) -> DataFrame:
    dag_metadata_data = get_dag_metadata(
        lineage_from_product_skip_list, dag_manual_mapping
    )

    metadata_df = spark_client.create_dataframe(
        [Row(**row) for row in dag_metadata_data],
        schema="layer string, dag_name string, database_name string, has_lineage_from_product boolean, owner string",
    ).drop("columns")

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
        f"""m={JOB_NAME}, datalake_bucket={datalake_bucket}, source={source},
        table_name={table_name}, execution_date_str={execution_date_str}
        msg=Job execution started."""
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
    dag_metadata_df = get_dag_metadata_df(
        spark_client, lineage_from_product_source_skip_list, dag_manual_mapping
    )
    dag_metadata_df = (
        SparkDataFrameService()
        .input(dag_metadata_df)
        .create_year_month_day_columns_from_date(execution_date)
        .optimize_partitions_by_partition_columns(partition_cols)
        .output()
    )

    # loaders
    s3_loader.load_df(
        df=dag_metadata_df,
        s3_path=f"{database_location}{table_name}",
        format_options=format_options,
        partitions=partition_cols,
    )
    spark_metastore_loader.update_metastore(
        dag_metadata_df,
        database_name,
        table_name,
        format_options,
        database_location,
        partition_cols,
    )
    spark_metastore_service.create_new_partitions_from_df(
        database_name=database_name,
        table_name=table_name,
        df=dag_metadata_df,
        partition_cols=partition_cols,
    )
    spark_metastore_service.refresh_table(database_name, table_name)
