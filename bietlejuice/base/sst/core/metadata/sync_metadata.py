import json
import logging
import traceback
from argparse import ArgumentParser
from collections import OrderedDict
from typing import Optional

from quintoandar_logger import QuintoAndarLogger
from pyspark.sql import DataFrame
from trino.exceptions import TrinoUserError

from bietlejuice.base.db.database_enum import DatabaseEnum
from bietlejuice.clients.db_clients.trino_client import TrinoClient
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.spark.base_spark import BaseDBUtils
from bietlejuice.base.spark.spark_metastore_helper import SparkMetastoreHelper

JOB_NAME = "sync_metadata"
logging.getLogger("py4j").setLevel(logging.ERROR)


def set_logger(job_name):
    return QuintoAndarLogger(job_name)


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


# trino sync helper functions
_TRINO_DELTA_CATALOG = "delta"


def _get_trino_client() -> TrinoClient:
    """
    Retrieves a TrinoClient pointing to the Delta catalog, using credentials
    stored in Databricks secrets.
    """
    dbutils = BaseDBUtils().get_dbutils()
    trino_creds = json.loads(dbutils.secrets.get("quintoandar", DatabaseEnum.TRINO))
    return TrinoClient(
        host=trino_creds["host"],
        port=int(trino_creds["port"]),
        user=trino_creds["user"],
        password=trino_creds["pwd"],
        catalog=_TRINO_DELTA_CATALOG,
        client_tags=["pipeline", "sst"],
    )


def _build_table_location(bucket: str, layer: str, schema: str, table_name: str) -> str:
    """
    Constructs the canonical S3 path for a Delta table following the datalake
    convention: ``s3a://{bucket}/{layer}/{schema}/{table_name}``.

    This avoids relying on ``DESCRIBE EXTENDED``, which returns the Databricks
    warehouse default when a table was created without an explicit location.

    :param bucket: S3 bucket name (e.g. ``5a-datalake-prod``).
    :param layer: Data layer (e.g. ``clean``).
    :param schema: Source schema name (e.g. ``salesforce``).
    :param table_name: Table name (e.g. ``events_case``).
    :return: s3a:// path to the table root.
    """
    return f"s3a://{bucket}/{layer}/{schema}/{table_name}"


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


def _sync_trino_metadata(
    target_table: str,
    table_location: Optional[str],
    df: DataFrame,
) -> None:
    """Sync Trino/Hive metastore after a Delta write.

    Resolves the Trino client, derives the database and table names from
    ``target_table``, and calls ``sync_trino_table_schema`` to register or
    update the table schema in the Delta catalog.

    Parameters
    ----------
    target_table : str
        Fully qualified Delta table name (``catalog.db.table`` or ``db.table``).
    table_location : str
        S3/HDFS path where the Delta table data lives. Required.
    df : DataFrame
        DataFrame whose ``dtypes`` describe the current table schema.
    """
    logger = set_logger("_sync_trino_metadata")

    if not table_location:
        raise ValueError(
            f"m=_sync_trino_metadata, target_table={target_table}, "
            "msg=table_location is required when sync_hive=True"
        )

    parts = target_table.split(".")
    db_name = parts[0] if len(parts) == 2 else ".".join(parts[:-1])
    tname = parts[-1]
    df_columns = OrderedDict((col.lower(), dtype) for col, dtype in df.dtypes)

    logger.info(
        f"m={logger.name}, db_name={db_name}, table_name={tname}, "
        f"table_location={table_location}, msg=Starting Trino metadata sync"
    )
    try:
        trino_client = _get_trino_client()
        logger.info(
            f"m={logger.name}, db_name={db_name}, table_name={tname}, "
            "msg=Trino client created successfully"
        )
        sync_trino_table_schema(
            trino_client, db_name, tname, table_location, df_columns
        )
        logger.info(
            f"m={logger.name}, db_name={db_name}, table_name={tname}, "
            "msg=Trino metadata sync completed successfully"
        )
    except Exception as e:
        logger.error(
            f"m={logger.name}, db_name={db_name}, table_name={tname}, "
            f"table_location={table_location}, msg=Trino metadata sync failed with: {e}"
        )
        raise


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
        table_location = _build_table_location(bucket, layer, schema, tname)
        sync_trino_table_schema(
            trino_client,
            spark_ms.spark_database_name,
            tname,
            table_location,
            tmeta["columns"],
        )

    logger.info(f"m={logger.name}, msg=Finished Trino metadata synchronization.")


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

    args = parser.parse_args()
    bucket = args.bucket
    layer = LayerEnum(args.layer).value
    schema = args.schema
    table_name = args.table_name
    all_tables_flag = args.all_tables_flag

    try:
        sync_trino_tables_metadata(bucket, layer, schema, table_name, all_tables_flag)
    except Exception as e:
        base_logger.error(
            f"m={JOB_NAME}, msg=sync_trino_tables_metadata failed with:\n\n\n {e}"
        )
        base_logger.error(traceback.format_exc())
        raise
