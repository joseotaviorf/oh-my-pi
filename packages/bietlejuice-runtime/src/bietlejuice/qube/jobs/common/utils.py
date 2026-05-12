import json
import os
from datetime import datetime

from pyspark.sql import Column, SparkSession
from pyspark.sql import functions as F


def timestamp_to_date_string(ts: int) -> str:
    """
    Convert Unix timestamp to yyyy-MM-dd date string.

    Args:
        ts: Unix timestamp (seconds since epoch)

    Returns:
        Date string in yyyy-MM-dd format
    """
    return datetime.fromtimestamp(ts).strftime("%Y-%m-%d")


def get_spark_session(app_name: str, env: str = "dev") -> SparkSession:
    from bietlejuice.base.spark.runtime_detector import RuntimeDetector

    if RuntimeDetector.is_emr():
        from bietlejuice.base.spark.spark_session_factory import (
            create_emr_spark_session,
        )

        return create_emr_spark_session(app_name)

    builder = SparkSession.builder.appName(app_name)

    # Set warehouse directory explicitly to avoid path issues
    warehouse_dir = os.path.join(os.getcwd(), "spark-warehouse")
    builder = builder.config("spark.sql.warehouse.dir", warehouse_dir)

    # Set persistent metastore location to avoid losing table metadata
    metastore_dir = os.path.join(os.getcwd(), "metastore_db")
    builder = builder.config(
        "spark.driver.extraJavaOptions", f"-Dderby.system.home={metastore_dir}"
    )

    if env in ["dev", "test", "local_test", "unittest"]:
        builder = (
            builder.config("spark.sql.shuffle.partitions", "1")
            .config("spark.default.parallelism", "1")
            .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
            .config(
                "spark.sql.catalog.spark_catalog",
                "org.apache.spark.sql.delta.catalog.DeltaCatalog",
            )
        )

    spark = builder.getOrCreate()

    # Ensure databases exist in dev/test
    if env in ["dev", "test", "local_test", "unittest"]:
        spark.sql("CREATE DATABASE IF NOT EXISTS core")
        spark.sql("CREATE DATABASE IF NOT EXISTS qube_dimensions")
        spark.sql("CREATE DATABASE IF NOT EXISTS qube_measures")
        spark.sql("CREATE DATABASE IF NOT EXISTS qube_metrics")

    return spark


def load_table(spark: SparkSession, table_name: str, env: str = "dev"):
    """
    Loads a table. If running locally (dev/test) and a CSV exists in qube_ps,
    loads from CSV. Otherwise uses spark.table(). If table doesn't exist in
    metastore but exists as Delta on disk, registers it first.

    For Databricks environments (forno/prod), automatically prepends the Unity
    Catalog namespace (e.g., quintoandar_forno) to table names.

    Note: env="unittest" skips CSV loading to use test fixtures.
    """
    # Check for CSV in qube_ps if we are in dev/test (but not unittest)
    if env in ["dev", "test", "local_test"]:
        # Extract short name. e.g. core.visit -> visit
        short_name = table_name.split(".")[-1]
        csv_path = os.path.join(os.getcwd(), "qube_ps", f"{short_name}.csv")

        if os.path.exists(csv_path):
            print(f"Loading {table_name} from local CSV: {csv_path}")
            return (
                spark.read.option("header", "true")
                .option("inferSchema", "true")
                .csv(csv_path)
            )

    # Prepend Unity Catalog namespace for Databricks environments
    qualified_table_name = table_name
    if env in ["forno", "prod"]:
        # Check if table name already has catalog prefix to avoid double-prefixing
        if not table_name.startswith("quintoandar_"):
            catalog = f"quintoandar_{env}"
            qualified_table_name = f"{catalog}.{table_name}"
            print(f"Qualified table name for Unity Catalog: {qualified_table_name}")

    # Try to load from metastore
    try:
        return spark.table(qualified_table_name)
    except Exception as e:
        # If table not found in metastore, check if Delta files exist on disk
        # This is only relevant for local dev/test environments
        if "TABLE_OR_VIEW_NOT_FOUND" in str(e) and env in [
            "dev",
            "test",
            "local_test",
            "unittest",
        ]:
            # Try to find and register Delta table (use original table_name for local paths)
            if "." in table_name:
                db_name, short_name = table_name.split(".", 1)
                delta_path = os.path.join(
                    os.getcwd(), "spark-warehouse", f"{db_name}.db", short_name
                )

                if os.path.exists(delta_path) and os.path.exists(
                    os.path.join(delta_path, "_delta_log")
                ):
                    print(
                        f"Registering existing Delta table: {table_name} from {delta_path}"
                    )
                    # Register the table
                    spark.sql(
                        f"""
                        CREATE TABLE IF NOT EXISTS {table_name}
                        USING DELTA
                        LOCATION '{delta_path}'
                    """
                    )
                    return spark.table(table_name)

        # If still can't load, re-raise original exception
        raise


def get_window_range(
    date_str: str,
    window_days: int,
    spark: SparkSession = None,
    table_name: str = None,
    date_col: str = None,
    env: str = "dev",
):
    """
    Returns (lo, hi) timestamps (integers) for the given window.
    If date_str is provided:
        hi = timestamp of the given date (midnight)
    Else (if date_str is None):
        Derive hi from the max(date_col) in table_name.

    lo = hi - window_days * 86400
    """
    if date_str:
        dt = datetime.strptime(date_str, "%Y-%m-%d")
        hi = int(dt.timestamp())
    else:
        if not all([spark, table_name, date_col]):
            raise ValueError(
                "If date is not provided, spark, table_name, and date_col must be provided to infer max date."
            )

        # Infer max date
        # We need to be careful about what date_col represents in source.
        # Usually source has many dates. We want the latest date available?
        # Or we want the "current" date?
        # If we are building for "latest", we check the max of the event date column?

        # Load table using load_table to support local CSVs
        df = load_table(spark, table_name, env)

        # Get max value. Assuming date_col is a timestamp or date string?
        # Spec usually defines date_expr.
        # We might need to evaluate date_expr to get the date column to take max of.
        # But evaluating date_expr on whole table is expensive.
        # Maybe we assume date_col is a physical column or we try to compute max?

        # Let's try to get max of the column specified.
        # If date_col is an expression like "unix_timestamp(dt, ...)", we can't easily "select max(expr)".
        # We can: df.select(F.max(F.expr(date_col))).collect()

        max_row = df.select(F.max(F.expr(date_col)).alias("max_date")).collect()
        max_val = max_row[0]["max_date"]

        if max_val is None:
            # If table is empty, default to now? or error?
            # Default to today midnight
            dt = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
            hi = int(dt.timestamp())
        else:
            # max_val should be the timestamp (long) because date_expr returns unix_timestamp
            hi = int(max_val)

    lo = hi - (window_days * 86400)
    return lo, hi


# JSON Helpers for Dimensions
def wrap_dimension_value(col_name: str, card: str, dtype: str) -> Column:
    """
    Wraps a column into the QUBE JSON schema structure using PySpark struct functions.
    Returns a Column expression that evaluates to the JSON string.
    """

    # We construct the struct structure first, then to_json

    if card == "single":
        if dtype == "string":
            # {"singleValued": {"stringValue": col}}
            struct_expr = F.struct(
                F.struct(F.col(col_name).alias("stringValue")).alias("singleValued")
            )
        elif dtype == "number":
            # {"singleValued": {"numberValue": col}}
            struct_expr = F.struct(
                F.struct(F.col(col_name).alias("numberValue")).alias("singleValued")
            )
        elif dtype == "boolean":
            # {"singleValued": {"booleanValue": col}}
            struct_expr = F.struct(
                F.struct(F.col(col_name).alias("booleanValue")).alias("singleValued")
            )
        else:
            raise ValueError(f"Unknown type: {dtype}")

    elif card == "multi":
        # For multi, the input col is expected to be an Array
        # We need to map transform the array to array of structs

        if dtype == "string":
            # {"multiValued": [{"stringValue": x}, ...]}
            struct_expr = F.struct(
                F.transform(
                    F.col(col_name), lambda x: F.struct(x.alias("stringValue"))
                ).alias("multiValued")
            )
        elif dtype == "number":
            struct_expr = F.struct(
                F.transform(
                    F.col(col_name), lambda x: F.struct(x.alias("numberValue"))
                ).alias("multiValued")
            )
        elif dtype == "boolean":
            struct_expr = F.struct(
                F.transform(
                    F.col(col_name), lambda x: F.struct(x.alias("booleanValue"))
                ).alias("multiValued")
            )
        else:
            raise ValueError(f"Unknown type: {dtype}")
    else:
        raise ValueError(f"Unknown cardinality: {card}")

    return F.to_json(struct_expr)


def get_default_json(card: str, dtype: str, defaults: dict = None) -> str:
    defaults = defaults or {}

    if card == "single":
        if dtype == "string":
            val = defaults.get("unknown_string", "UNKNOWN")
            return json.dumps({"singleValued": {"stringValue": val}})
        elif dtype == "number":
            val = defaults.get("unknown_number", 0.0)
            return json.dumps({"singleValued": {"numberValue": val}})
        elif dtype == "boolean":
            val = defaults.get("unknown_boolean", False)
            return json.dumps({"singleValued": {"booleanValue": val}})
    elif card == "multi":
        # Default for multi is usually empty list
        return json.dumps({"multiValued": []})

    return "{}"


def extract_dimension_value(col: Column, card: str, dtype: str) -> Column:
    """
    Inverse of wrap_dimension_value. extracting the primitive value(s) from JSON string.
    """
    # schema for from_json
    # We need to define the full schema
    # But we can use get_json_object for simplicity if performance allows,
    # or from_json with a schema.

    # Schema definition
    # json_schema = "singleValued STRUCT<stringValue: STRING, numberValue: DOUBLE, booleanValue: BOOLEAN>, multiValued ARRAY<STRUCT<stringValue: STRING, numberValue: DOUBLE, booleanValue: BOOLEAN>>"

    # Using from_json is cleaner and typed
    schema = "singleValued STRUCT<stringValue: STRING, numberValue: DOUBLE, booleanValue: BOOLEAN>, multiValued ARRAY<STRUCT<stringValue: STRING, numberValue: DOUBLE, booleanValue: BOOLEAN>>"

    parsed = F.from_json(col, schema)

    if card == "single":
        if dtype == "string":
            return parsed.getItem("singleValued").getItem("stringValue")
        elif dtype == "number":
            return parsed.getItem("singleValued").getItem("numberValue")
        elif dtype == "boolean":
            return parsed.getItem("singleValued").getItem("booleanValue")
    elif card == "multi":
        if dtype == "string":
            return parsed.getItem("multiValued").getField(
                "stringValue"
            )  # Returns array of strings
        elif dtype == "number":
            return parsed.getItem("multiValued").getField("numberValue")
        elif dtype == "boolean":
            return parsed.getItem("multiValued").getField("booleanValue")

    return F.lit(None)
