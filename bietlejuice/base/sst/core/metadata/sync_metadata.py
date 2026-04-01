import json
import logging
import traceback
from argparse import ArgumentParser
from collections import OrderedDict
from functools import partial

from hive_metastore_client import HiveMetastoreClient
from quintoandar_logger import QuintoAndarLogger
from pyspark.sql import DataFrame
from pyspark.sql.types import StructType, StructField, StringType
from trino.exceptions import TrinoUserError

from bietlejuice.base.db import DatalakeMetastoreMapping
from bietlejuice.base.db.database_enum import DatabaseEnum
from bietlejuice.clients.db_clients.trino_client import TrinoClient
from bietlejuice.base.hive import TableStorageDescriptorEnum
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.pipeline.metadata_type_enum import MetadataTypeEnum
from bietlejuice.base.spark.base_spark import BaseDBUtils
from bietlejuice.base.spark.spark_metastore_helper import SparkMetastoreHelper
from bietlejuice.base.service import ServiceEnum
from bietlejuice.loaders.hive_metastore_loader import HiveMetastoreLoader
from bietlejuice.services.dag_metadata_service import DAGMetadataService
from bietlejuice.services.metastore_services.hive_metastore_service import (
    HiveMetastoreService,
)
from bietlejuice.metadata_propagator_pipeline.full_content_lineage_pipeline import (
    FullContentLineagePipeline,
)
from bietlejuice.metadata_propagator_pipeline.lineage_tags_pipeline import (
    LineageTagsPipeline,
)
from bietlejuice.metadata_propagator_pipeline.raw_lineage_pipeline import (
    RawLineagePipeline,
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


def _get_clean_table_columns_from_df(
    df: DataFrame, partition_keys: list
) -> OrderedDict:
    """
    Infers the column schema from a clean table DataFrame,
    excluding partition keys and normalising column names to lowercase.
    """
    partition_keys_lower = {pk.lower() for pk in partition_keys}
    return OrderedDict(
        (col.lower(), dtype)
        for col, dtype in df.dtypes
        if col.lower() not in partition_keys_lower
    )


def _build_clean_tables_metadata(spark_ms):
    """
    Builds the full tables-metadata dict for the clean layer.
    Each table's DataFrame is read and passed to the column extractor instead of
    querying the Spark metastore catalog.
    """
    tables_metadata = {}
    for tname in spark_ms.get_table_names():
        partition_keys = spark_ms.spark_metastore_service.get_table_partition_keys(
            spark_ms.spark_database_name, tname
        )
        table_df = spark.table(f"{spark_ms.spark_database_name}.{tname}")  # noqa: F821
        columns = _get_clean_table_columns_from_df(table_df, partition_keys)
        tables_metadata[tname] = {
            "columns": columns,
            "partition_keys": partition_keys,
        }
    return tables_metadata


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
        f"partition_values={partition_values}, msg=Starting table partition values update"
    )

    hive_ms_loader.update_table_partitions(
        database_name=database_name,
        table_name=table_name,
        partition_values=partition_values,
    )

    logger.info(
        f"m={logger.name}, database_name={database_name}, table_name={table_name}, "
        f"partition_values={partition_values}, msg=Completed table partition values update"
    )


# trino sync helper functions
_TRINO_DELTA_CATALOG = "delta"


def _get_trino_client() -> TrinoClient:
    """
    Retrieves a TrinoClient pointing to the Delta catalog, using credentials
    stored in Databricks secrets.
    """
    trino_creds = json.loads(
        dbutils.secrets.get("quintoandar", DatabaseEnum.TRINO)  # noqa: F821
    )
    return TrinoClient(
        host=trino_creds["host"],
        port=int(trino_creds["port"]),
        user=trino_creds["user"],
        password=trino_creds["pwd"],
        catalog=_TRINO_DELTA_CATALOG,
        client_tags=["pipeline", "sst"],
    )


def _get_table_location(full_table_name: str) -> str:
    """
    Retrieves the physical storage location of a Spark table by running
    DESCRIBE EXTENDED and extracting the Location row.

    :param full_table_name: fully-qualified table name, e.g.
        ``datalake_salesforce_clean.events_case``
    :return: s3a:// path to the table root
    """
    table_info = spark.sql(  # noqa: F821
        f"DESCRIBE EXTENDED {full_table_name}"
    ).collect()
    location_rows = [r for r in table_info if r[0] == "Location"]
    if not location_rows:
        raise ValueError(
            f"m=_get_table_location, full_table_name={full_table_name}, "
            "msg=Could not find Location row in DESCRIBE EXTENDED output"
        )
    return location_rows[0][1].replace("s3://", "s3a://")


def sync_trino_table_schema(
    trino_client: TrinoClient,
    database_name: str,
    table_name: str,
    table_location: str,
    df_columns: OrderedDict,
) -> None:
    """
    Ensures the table is registered in Trino's Delta catalog and that its
    schema reflects the columns present in the DataFrame.

    For Delta tables Trino reads the schema directly from the Delta transaction
    log, so registering (or re-registering) the table is sufficient to pick up
    any column additions or type changes that were written by the clean pipeline.

    Args:
        trino_client (TrinoClient): Trino client pointing to the Delta catalog.
        database_name (str): Spark database name (e.g. ``datalake_salesforce_clean``).
        table_name (str): Table name (e.g. ``events_case``).
        table_location (str): Physical s3a:// path to the Delta table.
        df_columns (OrderedDict): Column name → Spark type mapping extracted
            from the clean DataFrame; used for logging and future validation.
    """
    logger = set_logger("sync_trino_table_schema")
    logger.info(
        f"m={logger.name}, database_name={database_name}, table_name={table_name}, "
        f"df_columns={list(df_columns.keys())}, msg=Starting Trino table schema sync"
    )

    try:
        table_ddl = trino_client.get_table_ddl(database_name, table_name)
        is_delta = (
            f"{_TRINO_DELTA_CATALOG}.{database_name}.{table_name}"
            in table_ddl.replace('"', "")
        )
        if is_delta:
            logger.info(
                f"m={logger.name}, database_name={database_name}, "
                f"table_name={table_name}, msg=Table already registered as Delta in Trino, skipping"
            )
            return
        logger.info(
            f"m={logger.name}, database_name={database_name}, table_name={table_name}, "
            "msg=Table registered but not as Delta, dropping before re-registration"
        )
        trino_client.drop_table(database_name, table_name)
    except TrinoUserError as e:
        if e.error_name != "TABLE_NOT_FOUND":
            raise
        logger.info(
            f"m={logger.name}, database_name={database_name}, table_name={table_name}, "
            "msg=Table not found in Trino, creating schema and registering"
        )
        trino_client.run(
            f"CREATE SCHEMA IF NOT EXISTS {_TRINO_DELTA_CATALOG}.{database_name}"
        )

    trino_client.register_table(
        schema_name=database_name,
        table_name=table_name,
        table_location=table_location,
    )
    logger.info(
        f"m={logger.name}, database_name={database_name}, table_name={table_name}, "
        "msg=Table successfully registered in Trino Delta catalog"
    )


# trino sync functions
def sync_trino_tables_metadata(bucket, layer, schema, table_name, all_tables_flag):
    """
    Reads the column schema from each clean-layer DataFrame and ensures the
    corresponding table is registered (and up-to-date) in Trino's Delta catalog.

    Args:
        bucket (str): S3 bucket name.
        layer (str): Data layer value (e.g. ``clean``).
        schema (str): Database/schema name (e.g. ``datalake_salesforce_clean``).
        table_name (str): Single table name, or None when ``all_tables_flag`` is True.
        all_tables_flag (bool): When True, syncs every table in the database.
    """
    logger = set_logger("sync_trino_tables_metadata")
    logger.info(
        f"m={logger.name}, bucket={bucket}, layer={layer}, schema={schema}, "
        f"table_name={table_name}, all_tables_flag={all_tables_flag}, "
        "msg=Job execution started."
    )

    spark_ms = SparkMetastoreHelper(bucket, layer, schema, table_name, all_tables_flag)
    spark_ms.validate_table_arguments()

    tables_metadata = _build_clean_tables_metadata(spark_ms)
    trino_client = _get_trino_client()

    for tname, tmeta in tables_metadata.items():
        full_table_name = f"{spark_ms.spark_database_name}.{tname}"
        table_location = _get_table_location(full_table_name)
        sync_trino_table_schema(
            trino_client,
            spark_ms.spark_database_name,
            tname,
            table_location,
            tmeta["columns"],
        )

    logger.info(f"m={logger.name}, msg=Finished Trino metadata synchronization.")


# hive sync funcions
def sync_metastore_table_structure(bucket, layer, schema, table_name, all_tables_flag):
    logger = set_logger("sync_metastore_table_structure")
    logger.info(
        f"m={logger.name}, bucket={bucket}, layer={layer}, schema={schema}, "
        f"table_name={table_name}, all_tables_flag={all_tables_flag}, "
        "msg=Job execution started."
    )
    spark_ms = SparkMetastoreHelper(bucket, layer, schema, table_name, all_tables_flag)
    spark_ms.validate_table_arguments()

    tables_metadata = _build_clean_tables_metadata(spark_ms)

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

    row_schema = StructType([StructField("table_name", StringType(), True)])
    spark_table_names = list(tables_metadata.keys())
    df = spark.createDataFrame(  # noqa: F821
        [(name,) for name in spark_table_names], schema=row_schema
    )
    df.foreach(
        lambda row: func(
            row.table_name,
            tables_metadata[row.table_name]["columns"],
            tables_metadata[row.table_name]["partition_keys"],
        )
    )
    logger.info(f"m={logger.name}, msg=Finished synchronization.")


def sync_metastore_table_partitions(bucket, layer, schema, table_name, all_tables_flag):
    logger = set_logger("sync_metastore_table_partitions")
    logger.info(
        f"m={logger.name}, bucket={bucket}, layer={layer}, schema={schema}, "
        f"table_name={table_name}, all_tables_flag={all_tables_flag}, "
        "msg=Job execution started."
    )

    spark_ms = SparkMetastoreHelper(bucket, layer, schema, table_name, all_tables_flag)
    spark_ms.validate_table_arguments()

    tables_metadata = _build_clean_tables_metadata(spark_ms)
    tables_partition_values = {}
    for tname, tmeta in tables_metadata.items():
        if tmeta["partition_keys"]:
            partition_values = spark_ms.get_spark_metastore_table_partition_values(
                tname
            )
            if not partition_values:
                logger.info(
                    f"m={logger.name}, table_name={tname}, "
                    "msg=Table partition values are empty"
                )
            tables_partition_values[tname] = partition_values

    hive_ms_host = _get_hive_metastore_host()
    hive_ms_client = HiveMetastoreClient(hive_ms_host)
    hive_ms_service = HiveMetastoreService(hive_ms_client)
    hive_ms_loader = HiveMetastoreLoader(hive_ms_service)

    func = partial(
        update_table_partitions, hive_ms_loader, spark_ms.spark_database_name
    )

    row_schema = StructType([StructField("table_name", StringType(), True)])
    spark_table_names = list(tables_partition_values.keys())
    df = spark.createDataFrame(  # noqa: F821
        [(name,) for name in spark_table_names], schema=row_schema
    )
    df.foreach(
        lambda row: func(row.table_name, tables_partition_values[row.table_name])
    )

    logger.info(f"m={JOB_NAME}, msg=Finished synchronization.")


# propagate metadata function
def propagate_metadata(layer, metadata_type, db_name_part, table_name):
    logger = set_logger("propagate_metadata")
    logger.info(
        f"m={logger.name}, layer={layer}, metadata_type={metadata_type}, db_name_part={db_name_part}, "
        f"table_name={table_name}, msg=Job execution started."
    )

    metadata_propagator_confs = dbutils.secrets.get(
        "quintoandar", ServiceEnum.METADATA_PROPAGATOR.value
    )
    metadata_propagator_confs_json = json.loads(metadata_propagator_confs)

    dl_ms_mapping = DatalakeMetastoreMapping(source=db_name_part, bucket="")
    database_name, _ = dl_ms_mapping.get_datalake_info_from_layer(layer)

    table_df = spark.table(f"{database_name}.{table_name}")  # noqa: F821
    columns_lineage = {
        col: {} for col in _get_clean_table_columns_from_df(table_df, partition_keys=[])
    }

    FullContentLineagePipeline(
        metadata_propagator_host=metadata_propagator_confs_json["host"],
        database_name=database_name,
        table_name=table_name,
        columns_lineage=columns_lineage,
    ).run()

    logger.info(
        f"m={logger.name}, layer={layer}, metadata_type={metadata_type}, db_name_part={db_name_part}, "
        f"table_name={table_name}, msg=Metadata propagated to Atlas."
    )


# propagate RAW metadata helper function
def _get_all_tables_metadata(spark_metastore_helper, metadata_type, relative_file_path):
    """
    Fetches all database tables metadata for the specified metadata type (tags or lineage).
    Column schemas are inferred from each table's DataFrame for FULL_CONTENT_LINEAGE.
    This metadata will be shared during the parallelised processing of table names RDD.
    """
    tables_spark_metadata = dict()
    for table_name in spark_metastore_helper.get_table_names():

        if metadata_type == MetadataTypeEnum.FULL_CONTENT_LINEAGE:
            table_df = spark.table(  # noqa: F821
                f"{spark_metastore_helper.spark_database_name}.{table_name}"
            )
            tables_spark_metadata[table_name] = {
                "name": table_name,
                "columns": _get_clean_table_columns_from_df(
                    table_df, partition_keys=[]
                ),
            }

        elif (
            metadata_type == MetadataTypeEnum.TAGS
            and DAGMetadataService.metadata_file_exists(
                relative_file_path, layer, table_name
            )
        ):
            tables_spark_metadata[table_name] = {"name": table_name}
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
        spark_ms, metadata_type, relative_file_path
    )
    spark_table_names = list(tables_metadata.keys())

    metadata_propagator_confs = dbutils.secrets.get(  # noqa: F821
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

    row_schema = StructType([StructField("table_name", StringType(), True)])
    df = spark.createDataFrame(  # noqa: F821
        [(name,) for name in spark_table_names], row_schema
    )
    df.foreach(
        lambda row: func(tables_metadata.get(row.table_name), product_database_name)
    )

    logger.info(f"m={logger.name}, msg=Job finished.")


base_logger = set_logger(JOB_NAME)

if __name__ == "__main__":
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
        "metadata_type_value",
        type=str,
        default=None,
        help="One of MetadataTypeEnum values",
    )
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
        "--bypass-trino",
        nargs="?",
        dest="bypass_trino",
        required=False,
        default=False,
        const=True,
        help="flag to bypass Trino Delta catalog sync",
    )

    args = parser.parse_args()
    bucket = args.bucket
    layer = LayerEnum(args.layer).value
    schema = args.schema
    table_name = args.table_name
    all_tables_flag = args.all_tables_flag
    metadata_type_value = args.metadata_type_value
    product_database_name = args.product_database_name
    bypass_hive = args.bypass_hive
    bypass_propagate = args.bypass_propagate
    bypass_trino = args.bypass_trino

    propagate_job = propagate_metadata
    propagate_params = [layer, metadata_type_value, schema, table_name]

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        global dbutils
        dbutils = base_dbutils.get_dbutils()

    jobs_to_run = []

    if not bypass_hive:
        jobs_to_run.extend(
            [
                {
                    "job": sync_metastore_table_structure,
                    "params": [bucket, layer, schema, table_name, all_tables_flag],
                },
                {
                    "job": sync_metastore_table_partitions,
                    "params": [bucket, layer, schema, table_name, all_tables_flag],
                },
            ]
        )
    if not bypass_trino:
        jobs_to_run.append(
            {
                "job": sync_trino_tables_metadata,
                "params": [bucket, layer, schema, table_name, all_tables_flag],
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
