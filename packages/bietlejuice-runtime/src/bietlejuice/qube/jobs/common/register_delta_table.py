"""
QUBE Register Delta Table Job

Registers QUBE Delta tables in Trino's Delta catalog for querying.
This is a QUBE-specific version of the cross-cutting register_delta_table job.
"""

import json
import logging
from argparse import ArgumentParser, Namespace
from typing import Optional

from trino.exceptions import TrinoUserError

from bietlejuice.base.db.database_enum import DatabaseEnum
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.qube.qube_table_naming import qube_validation_trino_table_name
from bietlejuice.base.spark.base_spark import BaseDBUtils
from bietlejuice.base.spark.spark_metastore_helper import SparkMetastoreHelper
from bietlejuice.base.validation.target_resolver import validation_database_location
from bietlejuice.clients.db_clients.trino_client import TrinoClient

JOB_NAME = "register_delta_table"
DELTA_CATALOG = "delta"
logging.getLogger("py4j").setLevel(logging.ERROR)


def parse_args() -> Namespace:
    """Parse command line arguments for table registration."""
    parser = ArgumentParser(JOB_NAME)
    parser.add_argument("bucket", type=str, help="S3 bucket name")
    parser.add_argument("layer", type=str, help="Data layer (e.g., 'qube')")
    parser.add_argument("schema", type=str, help="Schema/database name")
    parser.add_argument(
        "table_name",
        type=str,
        help="Base table name (without window suffix for QUBE tables)",
    )
    parser.add_argument(
        "--windows",
        type=str,
        default=None,
        help="Comma-separated window values for QUBE tables (e.g., '1,7,28'). If not provided, registers single table.",
    )
    parser.add_argument(
        "--target-database-name",
        type=str,
        default=None,
        help="Validation Trino schema (cluster_validation) when running validation DAGs.",
    )
    parser.add_argument(
        "--target-table-name",
        type=str,
        default=None,
        help="Validation table name prefix flag (per-window names derived like build jobs).",
    )

    return parser.parse_args()


def get_trino_client() -> TrinoClient:
    """
    Retrieves the Trino client using credentials from dbutils.

    On Databricks this reads Databricks secrets; on EMR ``BaseDBUtils`` resolves
    the same scope/key via AWS Secrets Manager.
    """
    base_dbutils = BaseDBUtils()
    dbutils = base_dbutils.get_dbutils()
    trino_credentials = json.loads(
        dbutils.secrets.get(  # pyright: ignore[reportUndefinedVariable]
            scope="quintoandar", key=DatabaseEnum.TRINO
        )
    )
    return TrinoClient(
        host=trino_credentials["host"],
        port=trino_credentials["port"],
        user=trino_credentials["user"],
        password=trino_credentials["pwd"],
        catalog=DELTA_CATALOG,
        client_tags=["pipeline", "qube"],
    )


def _to_trino_s3_location(location: str) -> str:
    return location.replace("s3://", "s3a://")


def _constructed_table_location(database_location: str, table_name: str) -> str:
    return _to_trino_s3_location(f"{database_location.rstrip('/')}/{table_name}")


def _full_table_name(
    spark_database_name: str, table_name: str, current_catalog: Optional[str]
) -> str:
    if current_catalog:
        return f"{current_catalog}.{spark_database_name}.{table_name}"
    return f"{spark_database_name}.{table_name}"


def _get_current_catalog(spark) -> Optional[str]:
    try:
        return spark.sql("SELECT current_catalog()").collect()[0][0]
    except Exception as exc:
        print(f"Could not determine current catalog: {exc}")
        return None


def _resolve_table_location_from_metastore(
    spark,
    full_table_name: str,
    fallback_location: str,
) -> str:
    try:
        table_info = spark.sql(f"DESCRIBE EXTENDED {full_table_name}").collect()
        location_row = [row for row in table_info if row[0] == "Location"]
        if not location_row:
            print(f"WARNING: Could not find location for table {full_table_name}")
            return fallback_location
        table_location = _to_trino_s3_location(location_row[0][1])
        print(
            f"Resolved table location from metastore for {full_table_name}: {table_location}"
        )
        return table_location
    except Exception as exc:
        error_message = str(exc)
        if (
            "TABLE_OR_VIEW_NOT_FOUND" in error_message
            or "cannot be found" in error_message
        ):
            raise
        print(f"WARNING: Failed to get location for {full_table_name}: {exc}")
        print(f"  Falling back to constructed location: {fallback_location}")
        return fallback_location


def _resolve_table_location(
    *,
    spark,
    spark_ms: SparkMetastoreHelper,
    table_name: str,
    current_catalog: Optional[str],
    prefer_metastore_lookup: bool,
) -> str:
    fallback_location = _constructed_table_location(
        spark_ms.database_location, table_name
    )
    if not prefer_metastore_lookup:
        print(
            f"Using constructed location for {spark_ms.spark_database_name}.{table_name}: {fallback_location}"
        )
        return fallback_location

    full_table_name = _full_table_name(
        spark_ms.spark_database_name, table_name, current_catalog
    )
    return _resolve_table_location_from_metastore(
        spark, full_table_name, fallback_location
    )


def _is_missing_table_error(error_message: str) -> bool:
    return (
        "TABLE_OR_VIEW_NOT_FOUND" in error_message
        or "cannot be found" in error_message
        or "No transaction log" in error_message
        or "DELTA_PATH_DOES_NOT_EXIST" in error_message
        or "PATH_NOT_FOUND" in error_message
    )


def _register_qube_table(
    *,
    trino_client: TrinoClient,
    spark,
    spark_ms: SparkMetastoreHelper,
    table_name: str,
    current_catalog: Optional[str],
    prefer_metastore_lookup: bool,
) -> None:
    table_location = _resolve_table_location(
        spark=spark,
        spark_ms=spark_ms,
        table_name=table_name,
        current_catalog=current_catalog,
        prefer_metastore_lookup=prefer_metastore_lookup,
    )
    print(
        f"Registering table: {spark_ms.spark_database_name}.{table_name} at {table_location}"
    )
    register_table(
        trino_client,
        spark_ms.spark_database_name,
        table_name,
        table_location,
    )


def register_table(
    trino_client: TrinoClient, database_name: str, table_name: str, table_location: str
) -> None:
    """
    Registers the table in Trino. If the schema does not exist, it will be created.
    If the table already exists but in parquet instead of Delta, it will be dropped.

    This is structured in a way to minimize queries to Trino. We found that most times
    that this function is called, the table is already registered as Delta. So we will
    query only once to find the DDL, realize that it is Delta, and do nothing.
    """
    try:
        table_ddl = trino_client.get_table_ddl(database_name, table_name)
        is_delta = f"{DELTA_CATALOG}.{database_name}.{table_name}" in table_ddl.replace(
            '"', ""
        )
        if not is_delta:  # The table exists but is not in Delta, so we need to drop it
            trino_client.drop_table(database_name, table_name)
        else:  # Already registered as Delta, nothing to be done
            return
    except TrinoUserError as e:
        if e.error_name != "TABLE_NOT_FOUND":
            raise e
        # If the table was not found, we can just proceed to create the schema and register the table
        trino_client.run(f"CREATE SCHEMA IF NOT EXISTS {DELTA_CATALOG}.{database_name}")

    # We will get to this point either if the table does not exist, or if it was dropped due to not being Delta
    trino_client.register_table(
        schema_name=database_name, table_name=table_name, table_location=table_location
    )


if __name__ == "__main__":
    args = parse_args()
    bucket = args.bucket
    layer = LayerEnum(args.layer).value
    schema = args.schema
    base_table_name = args.table_name
    target_database_name = args.target_database_name
    target_table_name = args.target_table_name
    is_validation = bool(target_database_name and target_table_name)

    from pyspark.sql import SparkSession

    from bietlejuice.base.spark.runtime_detector import RuntimeDetector

    if RuntimeDetector.is_emr():
        from bietlejuice.base.spark.spark_session_factory import (
            create_emr_spark_session,
        )

        spark = create_emr_spark_session("register_delta_table")
    else:
        spark = SparkSession.builder.getOrCreate()

    is_emr = RuntimeDetector.is_emr()
    current_catalog = None if is_emr else _get_current_catalog(spark)
    if current_catalog:
        print(f"Current catalog: {current_catalog}")

    spark_ms = SparkMetastoreHelper(
        bucket, layer, schema, base_table_name, all_tables=False
    )

    trino_client = get_trino_client()
    prefer_metastore_lookup = not is_emr

    if args.windows:
        windows = [int(w.strip()) for w in args.windows.split(",")]
        print(
            f"Registering {len(windows)} windowed tables for {base_table_name}: {windows}"
        )

        registered_count = 0
        skipped_count = 0

        for window in windows:
            windowed_table_name = f"{base_table_name}_{window}d"

            try:
                if is_validation:
                    prod_database = spark_ms.spark_database_name
                    trino_table_name = qube_validation_trino_table_name(
                        prod_database, windowed_table_name
                    )
                    table_location = _constructed_table_location(
                        validation_database_location(bucket, prod_database),
                        windowed_table_name,
                    )
                    print(
                        f"Validation mode: registering {target_database_name}.{trino_table_name} "
                        f"at {table_location}"
                    )
                    register_table(
                        trino_client,
                        target_database_name,
                        trino_table_name,
                        table_location,
                    )
                else:
                    _register_qube_table(
                        trino_client=trino_client,
                        spark=spark,
                        spark_ms=spark_ms,
                        table_name=windowed_table_name,
                        current_catalog=current_catalog,
                        prefer_metastore_lookup=prefer_metastore_lookup,
                    )
                registered_count += 1
            except Exception as exc:
                error_message = str(exc)
                if _is_missing_table_error(error_message):
                    if is_validation:
                        prod_database = spark_ms.spark_database_name
                        trino_table_name = qube_validation_trino_table_name(
                            prod_database, windowed_table_name
                        )
                        display_name = f"{target_database_name}.{trino_table_name}"
                    else:
                        display_name = _full_table_name(
                            spark_ms.spark_database_name,
                            windowed_table_name,
                            current_catalog,
                        )
                    print(
                        f"SKIPPING: Table {display_name} does not exist (likely skipped due to empty dataframe)"
                    )
                    skipped_count += 1
                    continue
                print(f"  Failed to register {windowed_table_name}: {exc}")
                skipped_count += 1

        print(f"\n{'=' * 60}")
        print(f"Registration Summary for {base_table_name}:")
        print(f"  Successfully registered: {registered_count}/{len(windows)} tables")
        print(f"  Skipped (not found): {skipped_count}/{len(windows)} tables")
        print(f"{'=' * 60}")
    else:
        full_table_name = _full_table_name(
            spark_ms.spark_database_name, base_table_name, current_catalog
        )

        try:
            _register_qube_table(
                trino_client=trino_client,
                spark=spark,
                spark_ms=spark_ms,
                table_name=base_table_name,
                current_catalog=current_catalog,
                prefer_metastore_lookup=prefer_metastore_lookup,
            )
            print(f"\n{'=' * 60}")
            print(f"Successfully registered table: {base_table_name}")
            print(f"{'=' * 60}")
        except Exception as exc:
            error_message = str(exc)
            if _is_missing_table_error(error_message):
                print(
                    f"SKIPPING: Table {full_table_name} does not exist (likely skipped due to empty dataframe)"
                )
            else:
                raise
