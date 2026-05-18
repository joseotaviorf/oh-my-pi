"""
QUBE Register Delta Table Job

Registers QUBE Delta tables in Trino's Delta catalog for querying.
This is a QUBE-specific version of the cross-cutting register_delta_table job.
"""

import json
import logging
from argparse import ArgumentParser, Namespace

from trino.exceptions import TrinoUserError

from bietlejuice.base.db.database_enum import DatabaseEnum
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.spark.base_spark import BaseDBUtils
from bietlejuice.base.spark.spark_metastore_helper import SparkMetastoreHelper
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

    return parser.parse_args()


def get_trino_client() -> TrinoClient:
    """
    Retrieves the Trino client using the credentials from Databricks Utils.
    The catalog will point to DELTA_CATALOG.
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

    # Initialize Spark to query table metadata
    from pyspark.sql import SparkSession

    from bietlejuice.base.spark.runtime_detector import RuntimeDetector

    if RuntimeDetector.is_emr():
        from bietlejuice.base.spark.spark_session_factory import (
            create_emr_spark_session,
        )

        spark = create_emr_spark_session("register_delta_table")
    else:
        spark = SparkSession.builder.getOrCreate()

    # Get current catalog for Unity Catalog environments
    try:
        current_catalog = spark.sql("SELECT current_catalog()").collect()[0][0]
        print(f"Current catalog: {current_catalog}")
    except Exception as e:
        print(f"Could not determine current catalog: {e}")
        current_catalog = None

    spark_ms = SparkMetastoreHelper(
        bucket, layer, schema, base_table_name, all_tables=False
    )

    trino_client = get_trino_client()

    # If windows parameter is provided, register each windowed table
    if args.windows:
        windows = [int(w.strip()) for w in args.windows.split(",")]
        print(
            f"Registering {len(windows)} windowed tables for {base_table_name}: {windows}"
        )

        registered_count = 0
        skipped_count = 0

        for window in windows:
            windowed_table_name = f"{base_table_name}_{window}d"

            # Build full table name with catalog prefix if available
            if current_catalog:
                full_table_name = f"{current_catalog}.{spark_ms.spark_database_name}.{windowed_table_name}"
            else:
                full_table_name = (
                    f"{spark_ms.spark_database_name}.{windowed_table_name}"
                )

            # Query actual table location from Unity Catalog instead of constructing it
            try:
                table_info = spark.sql(f"DESCRIBE EXTENDED {full_table_name}").collect()
                location_row = [row for row in table_info if row[0] == "Location"]

                if not location_row:
                    print(f"ERROR: Could not find location for table {full_table_name}")
                    continue

                table_location = location_row[0][1].replace("s3://", "s3a://")

                print(
                    f"Registering table: {spark_ms.spark_database_name}.{windowed_table_name} at {table_location}"
                )
                print("  (Location retrieved from Unity Catalog metadata)")

                register_table(
                    trino_client,
                    spark_ms.spark_database_name,
                    windowed_table_name,
                    table_location,
                )
                registered_count += 1
            except Exception as e:
                error_message = str(e)
                # Check if table doesn't exist (was skipped during build due to empty dataframe)
                if (
                    "TABLE_OR_VIEW_NOT_FOUND" in error_message
                    or "cannot be found" in error_message
                ):
                    print(
                        f"SKIPPING: Table {full_table_name} does not exist (likely skipped due to empty dataframe)"
                    )
                    skipped_count += 1
                    continue

                # For other errors, log and fallback to constructed path
                print(f"WARNING: Failed to get location for {full_table_name}: {e}")
                # Fallback to constructed path (for backwards compatibility)
                table_location = f"{spark_ms.database_location.rstrip('/')}/{windowed_table_name}".replace(
                    "s3://", "s3a://"
                )
                print(f"  Falling back to constructed location: {table_location}")
                try:
                    register_table(
                        trino_client,
                        spark_ms.spark_database_name,
                        windowed_table_name,
                        table_location,
                    )
                    registered_count += 1
                except Exception as reg_error:
                    print(f"  Failed to register with fallback path: {reg_error}")
                    print(f"  Skipping registration for {windowed_table_name}")
                    skipped_count += 1
                    continue

        # Print summary
        print(f"\n{'=' * 60}")
        print(f"Registration Summary for {base_table_name}:")
        print(f"  Successfully registered: {registered_count}/{len(windows)} tables")
        print(f"  Skipped (not found): {skipped_count}/{len(windows)} tables")
        print(f"{'=' * 60}")
    else:
        # Single table registration (non-windowed)
        # Build full table name with catalog prefix if available
        if current_catalog:
            full_table_name = (
                f"{current_catalog}.{spark_ms.spark_database_name}.{base_table_name}"
            )
        else:
            full_table_name = f"{spark_ms.spark_database_name}.{base_table_name}"

        try:
            table_info = spark.sql(f"DESCRIBE EXTENDED {full_table_name}").collect()
            location_row = [row for row in table_info if row[0] == "Location"]

            if not location_row:
                print(f"ERROR: Could not find location for table {full_table_name}")
                raise ValueError(f"Table {full_table_name} has no location metadata")

            table_location = location_row[0][1].replace("s3://", "s3a://")

            print(
                f"Registering table: {spark_ms.spark_database_name}.{base_table_name} at {table_location}"
            )
            print("  (Location retrieved from Unity Catalog metadata)")

            register_table(
                trino_client,
                spark_ms.spark_database_name,
                base_table_name,
                table_location,
            )
            print(f"\n{'=' * 60}")
            print(f"Successfully registered table: {base_table_name}")
            print(f"{'=' * 60}")
        except Exception as e:
            error_message = str(e)
            # Check if table doesn't exist (was skipped during build due to empty dataframe)
            if (
                "TABLE_OR_VIEW_NOT_FOUND" in error_message
                or "cannot be found" in error_message
            ):
                print(
                    f"SKIPPING: Table {full_table_name} does not exist (likely skipped due to empty dataframe)"
                )
                print("  No registration needed for non-existent table")
            else:
                # For other errors, log and fallback to constructed path
                print(f"WARNING: Failed to get location for {full_table_name}: {e}")
                # Fallback to constructed path (for backwards compatibility)
                table_location = f"{spark_ms.database_location.rstrip('/')}/{base_table_name}".replace(
                    "s3://", "s3a://"
                )
                print(f"  Falling back to constructed location: {table_location}")
                try:
                    register_table(
                        trino_client,
                        spark_ms.spark_database_name,
                        base_table_name,
                        table_location,
                    )
                except Exception as reg_error:
                    print(f"  Failed to register with fallback path: {reg_error}")
                    raise
