import json
import logging
import traceback
from argparse import ArgumentParser
from functools import partial

from hive_metastore_client import HiveMetastoreClient
from hive_metastore_client.builders import PartitionBuilder
from pyspark.sql.types import StringType, StructField, StructType
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreMapping, MetricMetastoreMapping
from bietlejuice.base.db.database_enum import DatabaseEnum
from bietlejuice.base.db.dw_metastore_mapping import DwMetastoreMapping
from bietlejuice.base.hive import TableStorageDescriptorEnum
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.pipeline.metadata_type_enum import MetadataTypeEnum
from bietlejuice.base.service.service_enum import ServiceEnum
from bietlejuice.base.spark.base_spark import BaseDBUtils
from bietlejuice.base.spark.runtime_detector import RuntimeDetector
from bietlejuice.base.spark.spark_metastore_helper import SparkMetastoreHelper
from bietlejuice.loaders.hive_metastore_loader import HiveMetastoreLoader
from bietlejuice.metadata_propagator_pipeline.lineage_tags_pipeline import (
    LineageTagsPipeline,
)
from bietlejuice.metadata_propagator_pipeline.raw_lineage_pipeline import (
    RawLineagePipeline,
)
from bietlejuice.services.dag_metadata_service import DAGMetadataService
from bietlejuice.services.metastore_services.hive_metastore_service import (
    HiveMetastoreService,
)
from bietlejuice.services.metastore_services.hive_sync_partition_utils import (
    should_skip_emr_hive_partition_sync,
)

JOB_NAME = "sync_metadata"
logging.getLogger("py4j").setLevel(logging.ERROR)


def set_logger(job_name):
    return QuintoAndarLogger(job_name)


# hive sync helper functions
def _get_hive_metastore_host():
    """
    Retrieves the Hive Metastore host stored in Databricks secrets
    """

    hm_confs = dbutils.secrets.get(  # noqa: F821
        "quintoandar", DatabaseEnum.HIVE_METASTORE
    )
    hm_confs_json = json.loads(hm_confs)
    return hm_confs_json["host"]


def update_table_structure(
    hive_ms_loader: HiveMetastoreLoader,
    database_name: str,
    database_location: str,
    storage_description: str,
    table_name: str,
    columns: list,
    partition_keys: list,
):
    """
    Updates columns and partition keys of a single table in Hive Metastore, dropping
    or creating them according to the values provided. Used for multiple concurrent
    requests that share the same Hive Metastore Loader object.
    Args:
        hive_ms_loader (HiveMetastoreLoader): Hive Metastore Loader object
        database_name (str): Name of the database from Databricks Metastore that
            contains the table(s) which partitions will be updated in Hive Metastore.
        database_location (str): File system location of the Spark database.
        storage_description (str): Storage format description for Hive Metastore table.
        table_name (str): Name of the table which structure will be updated in Hive
            Metastore.
        columns (str): List of columns that will be updated in Hive Metastore.
        partition_keys (List[str]): List of partition keys as strings.
    """
    logger = set_logger("sync_metastore_table_structure")

    logger.info(
        f"m={logger.name}, database_name={database_name}, table_name={table_name}, "
        f"columns={columns}, partition_keys={partition_keys}, "
        f"msg=Starting table schema and partition keys update"
    )

    hive_ms_loader.hive_metastore_service.create_database(database_name)
    hive_ms_loader.sync_metastore(
        database_name=database_name,
        table_name=table_name,
        database_location=database_location,
        table_schema=columns,
        partition_keys=partition_keys,
        format_info=storage_description,
        source_schema=columns,
    )

    logger.info(
        f"m={logger.name}, database_name={database_name}, table_name={table_name}, "
        f"columns={columns}, partition_keys={partition_keys}, "
        f"msg=Completed table schema and partition keys update"
    )


def update_table_partitions(
    hive_ms_loader: HiveMetastoreLoader,
    database_name: str,
    table_name: str,
    partition_values: list,
):
    """
    Updates partition values of a single table in Hive Metastore, dropping or creating
    them according to the values provided. Used for multiple concurrent requests that
    share the same Hive Metastore Loader object.
    Args:
        hive_ms_loader (HiveMetastoreLoader): Hive Metastore Loader object
        database_name (str): Name of the database from Databricks Metastore that
            contains the table(s) which partitions will be updated in Hive Metastore.
        table_name (str): Name of the table which partitions will be updated in Hive
            Metastore.
        partition_values (List[List[str]]): List of lists with partition values as
            strings.
    """
    logger = set_logger("sync_metastore_table_partitions")
    logger.info(
        f"m={logger.name}, database_name={database_name}, table_name={table_name}, "
        f"partition_count={len(partition_values)}, msg=Starting table partition values update"
    )

    hive_ms_loader.update_table_partitions(
        database_name=database_name,
        table_name=table_name,
        partition_values=partition_values,
    )

    logger.info(
        f"m={logger.name}, database_name={database_name}, table_name={table_name}, "
        f"partition_count={len(partition_values)}, msg=Completed table partition values update"
    )


# hive sync funcions
def sync_metastore_table_structure(
    bucket, layer, schema, table_name, all_tables_flag, transformation_grade=None
):
    logger = set_logger("sync_metastore_table_structure")
    logger.info(
        f"m={logger.name}, bucket={bucket}, layer={layer}, schema={schema}, "
        f"table_name={table_name}, all_tables_flag={all_tables_flag}, "
        "msg=Job execution started."
    )
    metastore_kwargs = {}
    if layer == "transformation":
        metastore_kwargs["transformation_grade"] = transformation_grade
    spark_ms = SparkMetastoreHelper(
        bucket,
        layer,
        schema,
        table_name,
        all_tables_flag,
        **metastore_kwargs,
    )
    spark_ms.validate_table_arguments()

    tables_metadata = spark_ms.get_all_tables_metadata()

    hive_ms_host = _get_hive_metastore_host()
    hive_ms_client = HiveMetastoreClient(hive_ms_host)
    hive_ms_service = HiveMetastoreService(hive_ms_client)
    hive_ms_loader = HiveMetastoreLoader(hive_ms_service)
    storage_description = TableStorageDescriptorEnum.from_layer(layer)

    func = partial(
        update_table_structure,
        hive_ms_loader,
        spark_ms.spark_database_name,
        spark_ms.database_location,
        storage_description,
    )

    schema = StructType([StructField("table_name", StringType(), True)])
    spark_table_names = list(tables_metadata.keys())
    df = spark.createDataFrame([(name,) for name in spark_table_names], schema=schema)
    df.foreach(
        lambda row: func(
            row.table_name,
            tables_metadata[row.table_name]["columns"],
            tables_metadata[row.table_name]["partition_keys"],
        )
    )
    logger.info(f"m={logger.name}, msg=Finished synchronization.")


def sync_metastore_table_partitions(
    bucket, layer, schema, table_name, all_tables_flag, transformation_grade=None
):
    logger = set_logger("sync_metastore_table_partitions")
    logger.info(
        f"m={logger.name}, bucket={bucket}, layer={layer}, schema={schema}, "
        f"table_name={table_name}, all_tables_flag={all_tables_flag}, "
        "msg=Job execution started."
    )

    metastore_kwargs = {}
    if layer == "transformation":
        metastore_kwargs["transformation_grade"] = transformation_grade
    spark_ms = SparkMetastoreHelper(
        bucket,
        layer,
        schema,
        table_name,
        all_tables_flag,
        **metastore_kwargs,
    )
    spark_ms.validate_table_arguments()

    tables_metadata = spark_ms.get_all_tables_metadata(get_partition_values=True)
    tables_partition_values = {
        table_name: table_metadata["partition_values"]
        for table_name, table_metadata in tables_metadata.items()
        if table_metadata["partition_keys"]
    }

    for table in tables_partition_values:
        if not tables_partition_values[table]:
            logger.info(
                f"m={logger.name}, table_name={table}, "
                f"partition_values={tables_partition_values[table]}, msg=Table partition values are empty"
            )

    hive_ms_host = _get_hive_metastore_host()
    hive_ms_client = HiveMetastoreClient(hive_ms_host)
    hive_ms_service = HiveMetastoreService(hive_ms_client)
    hive_ms_loader = HiveMetastoreLoader(hive_ms_service)

    func = partial(
        update_table_partitions, hive_ms_loader, spark_ms.spark_database_name
    )

    schema = StructType([StructField("table_name", StringType(), True)])
    spark_table_names = []
    for table in tables_partition_values:
        if should_skip_emr_hive_partition_sync(
            spark_ms.spark_database_name, table, spark=spark
        ):
            continue
        spark_table_names.append(table)
    df = spark.createDataFrame([(name,) for name in spark_table_names], schema=schema)
    df.foreach(
        lambda row: func(row.table_name, tables_partition_values[row.table_name])
    )

    logger.info(f"m={JOB_NAME}, msg=Finished synchronization.")


def sync_metastore_table_partitions_incremental(
    bucket, layer, schema, table_name, partition_values, transformation_grade=None
):
    """
    Adds the given partition values to the external Hive Metastore table without
    enumerating or reconciling existing partitions (no drops). Used by DAGs that
    opt into `incremental_partition_sync`, where the run's own partition is known
    upfront; the full reconciliation in `sync_metastore_table_partitions` remains
    the default and can be run manually to clean up drift or dropped partitions.
    """
    logger = set_logger("sync_metastore_table_partitions_incremental")
    logger.info(
        f"m={logger.name}, bucket={bucket}, layer={layer}, schema={schema}, "
        f"table_name={table_name}, partition_values={partition_values}, "
        "msg=Incremental partition sync started."
    )
    metastore_kwargs = {}
    if layer == "transformation":
        metastore_kwargs["transformation_grade"] = transformation_grade
    spark_ms = SparkMetastoreHelper(
        bucket,
        layer,
        schema,
        table_name,
        False,
        **metastore_kwargs,
    )
    spark_ms.validate_table_arguments()

    partitions = [
        PartitionBuilder(
            values=values,
            db_name=spark_ms.spark_database_name,
            table_name=table_name,
        ).build()
        for values in partition_values
    ]

    hive_ms_host = _get_hive_metastore_host()
    hive_ms_client = HiveMetastoreClient(hive_ms_host)
    hive_ms_service = HiveMetastoreService(hive_ms_client)
    hive_ms_service.add_partitions_to_table(
        spark_ms.spark_database_name, table_name, partitions
    )
    logger.info(f"m={logger.name}, msg=Finished incremental synchronization.")


# propagate metadata function
def propagate_metadata(
    layer, metadata_type, db_name_part, table_name, transformation_grade=None
):
    logger = set_logger("propagate_metadata")
    logger.info(
        f"m={logger.name}, layer={layer}, metadata_type={metadata_type}, db_name_part={db_name_part}, "
        f"table_name={table_name},  msg=Job execution started."
    )

    metadata_propagator_confs = dbutils.secrets.get(
        "quintoandar", ServiceEnum.METADATA_PROPAGATOR.value
    )
    metadata_propagator_confs_json = json.loads(metadata_propagator_confs)
    metadata_type = MetadataTypeEnum(metadata_type)

    if layer == LayerEnum.DW.value:
        dw_ms_mapping = DwMetastoreMapping(
            source=db_name_part, bucket=""
        ).get_all_dw_info()
        database_name = dw_ms_mapping["dw_schema_databricks"]
    elif layer == LayerEnum.METRIC.value:
        metric_ms_mapping = MetricMetastoreMapping(source=db_name_part, bucket="")
        database_name, _ = metric_ms_mapping.get_metric_info()
    else:
        dl_ms_mapping = DatalakeMetastoreMapping(source=db_name_part, bucket="")
        database_name, _ = dl_ms_mapping.get_datalake_info_from_layer(
            layer, transformation_grade=transformation_grade
        )

    LineageTagsPipeline(
        metadata_propagator_host=metadata_propagator_confs_json["host"],
        database_name=database_name,
        table_name=table_name,
        metadata_type=metadata_type,
    ).run()

    logger.info(
        f"m={logger.name}, layer={layer}, metadata_type={metadata_type}, db_name_part={db_name_part}, "
        f"table_name={table_name}, msg=Metadata propagated to Atlas."
    )


# propagate RAW metadata helper function
def _get_all_tables_metadata(
    spark_metastore_helper, metadata_type, relative_file_path, layer
):
    """
    Fetches all database tables metadata for the specified metadata type (tags or lineage)
    This metadata will be shared during the parallelized processing of table names RDD.
    """
    tables_spark_metadata = dict()
    for table_name in spark_metastore_helper.get_table_names():
        if metadata_type == MetadataTypeEnum.FULL_CONTENT_LINEAGE:
            spark_ms_table_columns = (
                spark_metastore_helper.get_spark_metastore_table_columns(table_name)
            )
            tables_spark_metadata[table_name] = dict()
            tables_spark_metadata[table_name]["name"] = table_name
            tables_spark_metadata[table_name]["columns"] = spark_ms_table_columns

        elif (
            metadata_type == MetadataTypeEnum.TAGS
            and DAGMetadataService.metadata_file_exists(
                relative_file_path, layer, table_name
            )
        ):
            tables_spark_metadata[table_name] = dict()
            tables_spark_metadata[table_name]["name"] = table_name
    return tables_spark_metadata


def propagate_table(
    metadata_propagator_host,
    layer,
    metadata_type,
    database_name,
    table_spark_metadata,
    product_database_name=None,
):
    logger = set_logger("propagate_raw_metadata")
    logger.info(
        f"m={logger.name}, layer={layer}, database_name={database_name}, "
        f"table_name={table_spark_metadata['name']}, metadata_type={metadata_type}, "
        f"msg=Starting table metadata propagation."
    )

    if metadata_type == MetadataTypeEnum.TAGS:
        LineageTagsPipeline(
            metadata_propagator_host=metadata_propagator_host,
            database_name=database_name,
            table_name=table_spark_metadata["name"],
            metadata_type=metadata_type,
        ).run()

    if metadata_type == MetadataTypeEnum.FULL_CONTENT_LINEAGE:
        RawLineagePipeline(
            metadata_propagator_host=metadata_propagator_host,
            database_name=database_name,
            table_name=table_spark_metadata["name"],
            table_schema=table_spark_metadata["columns"],
            product_database_name=product_database_name,
        ).run()

    logger.info(
        f"m={logger.name}, layer={layer}, database_name={database_name}, "
        f"table_name={table_spark_metadata['name']}, metadata_type={metadata_type}, "
        f"product_database_name={product_database_name}"
        f"msg=Table metadata propagated."
    )


# propagate RAW metadata function
def propagate_raw_metadata(
    layer_value,
    metadata_type_value,
    target_database_base_name,
    relative_file_path,
    product_database_name,
    table_name,
    all_tables,
):
    logger = set_logger("propagate_raw_metadata")

    layer = LayerEnum(layer_value).value
    metadata_type = MetadataTypeEnum(metadata_type_value)

    if metadata_type == MetadataTypeEnum.FULL_CONTENT_LINEAGE and (
        not product_database_name
    ):
        error_msg = (
            f"m={logger.name}, metadata_type={metadata_type}, "
            f"product_database_name={product_database_name}, "
            f"msg=Product_database_name must be provided when metadata type is full_content_lineage"
        )
        logger.error(error_msg)
        raise ValueError(error_msg)

    logger.info(
        f"m={logger.name}, "
        f"layer={layer}, metadata_type={metadata_type}, target_database_base_name={target_database_base_name}, "
        f"table_name={table_name}, all_tables={all_tables}, msg=Job execution started."
    )

    spark_ms = SparkMetastoreHelper(
        "", layer, target_database_base_name, table_name, all_tables
    )
    spark_ms.validate_table_arguments()

    tables_metadata = _get_all_tables_metadata(
        spark_ms, metadata_type, relative_file_path, layer
    )
    spark_table_names = list(tables_metadata.keys())

    metadata_propagator_confs = dbutils.secrets.get(
        "quintoandar", ServiceEnum.METADATA_PROPAGATOR.value
    )
    metadata_propagator_confs_json = json.loads(metadata_propagator_confs)

    func = partial(
        propagate_table,
        metadata_propagator_confs_json["host"],
        layer,
        metadata_type,
        spark_ms.spark_database_name,
    )

    schema = StructType([StructField("table_name", StringType(), True)])
    df = spark.createDataFrame([(name,) for name in spark_table_names], schema)
    df.foreach(
        lambda row: func(tables_metadata.get(row.table_name), product_database_name)
    )

    logger.info(f"m={logger.name}, msg=Job finished.")


base_logger = set_logger(JOB_NAME)


def build_arg_parser():
    parser = ArgumentParser(JOB_NAME)
    parser.add_argument("bucket", type=str)
    parser.add_argument("layer", type=str)
    parser.add_argument("schema", type=str)
    parser.add_argument(
        "--table-name",
        type=str,
        dest="table_name",
        required=False,
        help="table name for single sync",
    )
    parser.add_argument(
        "--all-tables",
        nargs="?",
        dest="all_tables_flag",
        required=False,
        default=False,
        const=True,
        help="flag to sync all tables from database",
    )
    parser.add_argument(
        "--metadata-type",
        dest="metadata_type_value",
        default=None,
        help="One of MetadataTypeEnum values",
    )
    parser.add_argument("relative_file_path", default=None, type=str)
    parser.add_argument(
        "--product-database-name",
        type=str,
        dest="product_database_name",
        required=False,
        default=None,
        help="product database name, used in product to raw lineage",
    )
    parser.add_argument(
        "--bypass-hive",
        nargs="?",
        dest="bypass_hive",
        required=False,
        default=False,
        const=True,
        help="flag to bypass hive sync for CDC loads",
    )
    parser.add_argument(
        "--bypass-propagate",
        nargs="?",
        dest="bypass_propagate",
        required=False,
        default=False,
        const=True,
        help="flag to bypass propagation of lineage",
    )
    parser.add_argument(
        "--partition-values",
        type=str,
        dest="partition_values",
        required=False,
        default=None,
        help=(
            'JSON list of partition-value lists (e.g. \'[["2026", "7", "3"]]\'). '
            "When set, skips full partition reconciliation and only adds these "
            "partitions to the external Hive metastore (no drops)."
        ),
    )
    parser.add_argument(
        "--transformation-grade",
        type=str,
        choices=["clean", "curated"],
        required=False,
        default=None,
        help="Required when layer is transformation: clean or curated",
    )

    return parser


def main():
    args = build_arg_parser().parse_args()
    global spark
    if RuntimeDetector.is_emr():
        from bietlejuice.base.spark.spark_session_factory import (
            create_emr_spark_session,
        )

        spark = create_emr_spark_session(JOB_NAME)
    bucket = args.bucket
    layer = LayerEnum(args.layer).value
    schema = args.schema
    table_name = args.table_name
    all_tables_flag = args.all_tables_flag
    metadata_type_value = args.metadata_type_value
    relative_file_path = args.relative_file_path
    product_database_name = args.product_database_name
    bypass_hive = args.bypass_hive
    bypass_propagate = args.bypass_propagate
    transformation_grade = args.transformation_grade

    if layer == LayerEnum.RAW.value:
        propagate_job = propagate_raw_metadata
        propagate_params = [
            layer,
            metadata_type_value,
            schema,
            relative_file_path,
            product_database_name,
            table_name,
            all_tables_flag,
        ]
    else:
        propagate_job = propagate_metadata
        propagate_params = [
            layer,
            metadata_type_value,
            schema,
            table_name,
            transformation_grade,
        ]

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        global dbutils
        dbutils = base_dbutils.get_dbutils()

    jobs_to_run = []

    if not bypass_hive:
        jobs_to_run.append(
            {
                "job": sync_metastore_table_structure,
                "params": [
                    bucket,
                    layer,
                    schema,
                    table_name,
                    all_tables_flag,
                    transformation_grade,
                ],
            }
        )
        if args.partition_values:
            partition_values = json.loads(args.partition_values)
            if not table_name or all_tables_flag:
                raise ValueError(
                    "--partition-values requires --table-name single-table mode"
                )
            if partition_values:
                jobs_to_run.append(
                    {
                        "job": sync_metastore_table_partitions_incremental,
                        "params": [
                            bucket,
                            layer,
                            schema,
                            table_name,
                            partition_values,
                            transformation_grade,
                        ],
                    }
                )
        else:
            jobs_to_run.append(
                {
                    "job": sync_metastore_table_partitions,
                    "params": [
                        bucket,
                        layer,
                        schema,
                        table_name,
                        all_tables_flag,
                        transformation_grade,
                    ],
                }
            )
    if not bypass_propagate:
        jobs_to_run.append({"job": propagate_job, "params": propagate_params})

    exceptions = []
    for job_dict in jobs_to_run:
        try:
            print(f"\n\n{0:=<50} - {str(job_dict['job'])}")
            job_dict["job"](*job_dict["params"])
        except Exception as e:
            base_logger.error(
                f"m={JOB_NAME}, msg={job_dict['job']} failed with:\n\n\n {e} \n\n\nPassing to next before raising exception."
            )
            base_logger.error(traceback.format_exc())
            exceptions.append(e)

    if exceptions:
        raise Exception(exceptions)


if __name__ == "__main__":
    from bietlejuice.base.spark.spark_session_factory import run_spark_entrypoint

    run_spark_entrypoint(main)
