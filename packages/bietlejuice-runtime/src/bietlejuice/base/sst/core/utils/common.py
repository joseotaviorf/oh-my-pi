# Handle utils to be used across multiple jobs

import re
from argparse import ArgumentParser
from collections import Counter
from functools import wraps
from typing import Callable, List, Optional, Tuple, Union

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark.delta_secondary_catalog_sync import (
    sync_delta_write_to_secondary_catalog,
)
from bietlejuice.base.sst.core.metadata.sync_metadata import sync_trino_metadata

logger = QuintoAndarLogger("sst.common")


def default_args(
    *, optional_args=None, description="SSt default args Decorator"
) -> Callable:
    """
    Decorator that parses CLI arguments and passes a single `argparse.Namespace`
    as the first argument to the wrapped Spark job entrypoint.

    The decorated function receives the parsed namespace (e.g. ``args.job_name``,
    ``args.env``) instead of raw argv, and can be tested by passing
    ``argv=[...]`` or ``args=[...]`` to the wrapper.

    Default required arguments (flag-style, with aliases):
      - ``job_name`` (--job_name / --job-name)
      - ``env`` (--env / --environment), e.g. dev/forno/prod
      - ``target_schema`` (--target_schema / --target-schema)
      - ``target_table`` (--target_table / --target-table)

    Parameters
    ----------
    optional_args : list of dict, optional
        Extra argument specs to add to the parser. Each dict can include
        "name", "flags", "type", "required", "help", "default" (see
        _add_flag_arg for format). If omitted, only the default args above
        are used.
    description : str, optional
        Description shown in the ArgumentParser help (e.g. ``--help``).

    Returns
    -------
    Callable
        A decorator that, when applied to a function, returns a wrapper
        that parses CLI args and calls the function with (parsed_namespace, ...).

    Example
    -------
    >>> @default_args(optional_args=[{"name": "partition_date", "type": str}])
    ... def main(args):
    ...     print(args.job_name, args.env, args.partition_date)
    ...
    >>> main(argv=["--job_name", "my_dag", "--env", "forno", ...])
    """

    # Flag-first defaults (with aliases for backward/explicit naming)
    DEFAULT_ARGS = [
        dict(
            name="job_name",
            flags=["--job_name", "--job-name"],
            type=str,
            required=True,
            help="DAG Name",
        ),
        dict(
            name="env",
            flags=["--env", "--environment"],
            type=str,
            required=True,
            help="Environment: dev/forno/prod",
        ),
        dict(
            name="target_schema",
            flags=["--target_schema", "--target-schema"],
            type=str,
            required=False,
            help="Target Database Name",
        ),
        dict(
            name="target_table",
            flags=["--target_table", "--target-table"],
            type=str,
            required=False,
            help="Target Table Name",
        ),
    ]

    optional_args = list(optional_args or [])

    def _add_flag_arg(parser: ArgumentParser, spec: dict) -> None:
        """
        Add a flag-style argument from a spec dict.

        Spec format (recommended):
          {
            "name": "partition_date",
            "flags": ["--partition_date", "--partition-date"],
            "type": str,
            "required": True/False,
            "help": "...",
            "default": ...,
          }

        Back-compat:
          If "flags" is omitted, we infer ["--<name>"].
        """
        name = spec["name"]
        flags = spec.get("flags") or [f"--{name}"]

        # dest ensures Namespace attribute uses `name` even if flags vary
        kwargs = {k: v for k, v in spec.items() if k not in {"name", "flags"}}
        kwargs.setdefault("dest", name)

        # If neither required nor default is provided, argparse treats it as optional
        parser.add_argument(*flags, **kwargs)

    def decorator(func: Callable) -> Callable:
        @wraps(func)
        def wrapper(*f_args, argv=None, args=None, **f_kwargs):
            # Back-compat: allow args=... as an alias for argv=...
            if argv is None and args is not None:
                argv = args

            parser = ArgumentParser(description=description)

            # Add defaults + optional extensions
            for spec in DEFAULT_ARGS:
                _add_flag_arg(parser, spec)
            for spec in optional_args:
                _add_flag_arg(parser, spec)

            parsed, unknown = parser.parse_known_args(argv)  # argv=None => sys.argv
            if unknown:
                logger.warning(f"m=default_args, msg=Unknown arguments: {unknown}")
            return func(parsed, *f_args, **f_kwargs)

        return wrapper

    return decorator


def build_partition_filter(filters: dict[str, object]) -> str:
    """
    Helper function to build a partition filter from a dictionary of filters.

    Parameters
    ----------
    filters : dict[str, object]
        Dictionary of filters.

    Returns
    -------
    str: A string in A SQL format for the partition_filter

    e.g:
    -------
    >>> build_partition_filter({"partition_date": "2026-01-01", "partition_hour": "00"})
    "partition_date = '2026-01-01' AND partition_hour = '00'"

    >>> build_partition_filter({"partition_date": "2026-01-01", "partition_hour": "00", "event_table":"events_case"})
    "partition_date = '2026-01-01' AND partition_hour = '00' AND event_table = 'events_case'"

    build_partition_filter({"partition_date": "2026-01-01", "threshold_time_hours": 24, "event_table":"events_case"})
    "partition_date = '2026-01-01' AND threshold_time_hours = 42 AND event_table = 'events_case'"
    """

    expressions = []

    for column, value in filters.items():
        if isinstance(value, str):
            expressions.append(f"{column} = '{value}'")
        else:
            expressions.append(f"{column} = {value}")

    return " AND\n".join(expressions)


@logger()
def retrieve_database_metadata(
    environment: str, schema: str, bucket: str, layer: str
) -> Tuple[str, str]:
    """
    Retrieve the Databricks database name and path for a given layer from the datalake metastore.

    Wrapper around DatalakeMetastoreService.get_db_info that returns the
    layer-specific database name and S3 path (e.g. for raw, clean, enrich).

    Parameters
    ----------
    environment : str
        Environment (e.g. "forno", "prod").
    schema : str
        Schema/database identifier in the metastore.
    bucket : str
        Datalake bucket name.
    layer : str
        Data layer (e.g. "raw", "clean", "enrich", "dw"). Case-insensitive.

    Returns
    -------
    tuple[str, str]
        (database_name, database_location) for the given layer.
    """
    db_info = DatalakeMetastoreService.get_db_info(environment, schema, bucket)
    database_name = db_info[f"db_{layer.lower()}_databricks"]
    database_location = db_info[f"db_{layer.lower()}_path"]

    return database_name, database_location


def _table_exists(spark: SparkSession, target_table: str) -> bool:
    """Return True if the Delta table exists in the catalog."""
    return spark.catalog.tableExists(target_table)


@logger()
def _require_qualified_table_name(target_table: str) -> None:
    """
    Raise ValueError if target_table is not a qualified table name (e.g. database.table).
    Prevents silently writing to the default database when only a database name is passed.
    """
    logger.info(
        f"m=require_qualified_table_name, msg=Checking if table {target_table} is a qualified name"
    )
    parts = target_table.strip().split(".")
    if len(parts) < 2:
        logger.error(
            f"m=require_qualified_table_name, msg=Table {target_table} is not a qualified name"
        )
        raise ValueError(
            f"target_table must be a qualified name (e.g. database.table), got: {target_table!r}. "
            "Passing only a database name writes to the default database instead of the intended table."
        )


@logger(exclude=["df", "current"], exclude_return=True)
def safe_column_union(
    df: DataFrame, current: Union[str, DataFrame], spark: SparkSession = None
) -> DataFrame:
    """
    Union of columns from df and current: result has all columns from both.

    - Columns only in current are added to df as nulls cast to current type.
    - Columns only in df are kept (new columns).
    - Column order: current columns first, then new columns from df.

    Parameters
    ----------
    df : DataFrame
        Source DataFrame.
    current : str or DataFrame
        Current table name (e.g. "catalog.database.table") or a DataFrame
        whose schema defines the current columns and types.

    Returns
    -------
    DataFrame
        DataFrame with union of columns, conformed for safe merge/write.
    """
    spark = spark or df.sparkSession
    current_df = spark.read.table(current) if isinstance(current, str) else current

    current_schema = {f.name: f.dataType for f in current_df.schema}
    df_schema = {f.name: f.dataType for f in df.schema}

    current_columns = [f.name for f in current_df.schema]
    new_columns = [c for c in df.columns if c not in current_schema]

    all_columns = current_columns + new_columns

    # Add missing columns to df (cast to current types)
    for col in current_columns:
        if col not in df.columns:
            df = df.withColumn(col, F.lit(None).cast(current_schema[col]))

    # Add new columns to current (cast to df types)
    for col in new_columns:
        if col not in current_df.columns:
            current_df = current_df.withColumn(col, F.lit(None).cast(df_schema[col]))

    return current_df.select(all_columns).unionByName(df.select(all_columns))


@logger(exclude_return=False)
def _safe_merge_schema(spark: SparkSession, df: DataFrame, table: str) -> DataFrame:
    """
    Conform an incoming DataFrame to an existing target table schema.

    The function identifies:
      - new columns in `df` that are not in the target table schema (`updates`)
      - columns present in the target table but missing from `df` (`missing_columns`)

    Missing target columns are added to `df` as null values cast to the
    target data types. The output column order is deterministic:
    existing target columns first, followed by new incoming columns.

    Parameters
    ----------
    spark : SparkSession
        Active Spark session used to read target table schema.
    df : DataFrame
        Incoming DataFrame to be conformed.
    table : str
        Fully qualified target table name.

    Returns
    -------
    DataFrame
        DataFrame aligned to target schema plus any new incoming columns.
    """

    target_table = spark.read.table(table)
    target_schema = {field.name: field.dataType for field in target_table.schema}
    updates = set(df.columns) - set(target_schema.keys())
    missing_columns = set(target_schema.keys()) - set(df.columns)

    logger.info(f"m=_safe_merge_schema, msg=Checking for new columns in {target_table}")
    logger.info(f"m=_safe_merge_schema, msg=New columns: {updates}")

    # Conform DF to avoid overwriting schema with missing column or incorrect type
    if missing_columns:
        logger.info(
            f"m=_safe_merge_schema, msg=Conforming schema. Adding missing columns to {target_table}"
        )
        for col in missing_columns:
            if col not in df.columns:
                df = df.withColumn(col, F.lit(None).cast(target_schema[col]))

    ordered_columns = list(target_schema.keys()) + list(updates)
    return df.select(ordered_columns)


def _resolve_glue_table_name(target_table: str) -> str:
    """Return ``database.table`` for secondary catalog sync (Glue / UC REST).

    Three-part UC names (``catalog.database.table``) map to ``database.table``.
    Two-part names are returned unchanged.
    """
    parts = target_table.split(".")
    if len(parts) == 2:
        return target_table
    if len(parts) >= 3:
        return f"{parts[-2]}.{parts[-1]}"
    raise ValueError(
        f"target_table must be a qualified name (database.table), got: {target_table}"
    )


def _post_write_catalog_sync(
    spark: SparkSession,
    df: DataFrame,
    target_table: str,
    table_location: str,
    partition_cols: Optional[List[str]],
    sync_hive: bool,
    sync_secondary_catalog: bool,
) -> None:
    """Register table metadata in Trino and/or the secondary catalog after a write."""
    if sync_hive:
        sync_trino_metadata(target_table, table_location, df)
        logger.info(
            f"m=validate_and_write, target_table={target_table}, "
            "msg=Trino metadata sync completed"
        )
    else:
        logger.info(
            f"m=validate_and_write, target_table={target_table}, "
            "msg=Trino metadata sync skipped (sync_hive=False)"
        )

    if not sync_secondary_catalog:
        logger.info(
            f"m=validate_and_write, target_table={target_table}, "
            "msg=Secondary catalog sync skipped (sync_secondary_catalog=False)"
        )
        return

    if not table_location:
        raise ValueError(
            f"m=validate_and_write, target_table={target_table}, "
            "msg=table_location is required when sync_secondary_catalog=True"
        )

    glue_table_name = _resolve_glue_table_name(target_table)
    sync_delta_write_to_secondary_catalog(
        spark=spark,
        full_table_name=glue_table_name,
        table_location_s3=table_location,
        source_df=df,
        partition_col_names=list(partition_cols or []),
    )
    logger.info(
        f"m=validate_and_write, target_table={target_table}, "
        "msg=Secondary catalog sync completed"
    )


@logger(exclude=["df"], exclude_return=False)
def validate_and_write(
    spark: SparkSession,
    df: DataFrame,
    target_table: str,
    table_location: str,
    partition_filter: str = None,
    partition_cols: Optional[List[str]] = None,
    overwrite_schema: bool = False,
    append: bool = False,
    sync_hive: bool = False,
    sync_secondary_catalog: bool = False,
):
    """
    Validate and write a filtered subset of columns to a Delta table using
    partition-based overwrite.

    If the table does not exist, it is created with the full DataFrame and
    the given partition columns. If it exists, data matching the partition
    filter is overwritten using `replaceWhere`, and the write is limited to
    the existing table columns (read from the table when cols is None).

    Parameters
    ----------
    df : DataFrame
        Source DataFrame to be written.
    target_table : str
        Fully qualified target Delta table name e.g. target_catalog.target_database.target_table
    partition_filter : str
        SQL predicate used by `replaceWhere` to limit the overwrite scope.
    partition_cols : List[str], optional
        Partition column names when creating the table. If None or empty, table is created unpartitioned.
    overwrite_schema : bool
        Whether to overwrite the schema of the target table, for safety the default is False to avoid accidental schema changes.
    append: bool
        Whether to append the DataFrame to the target table, the default is False to overwrite the partition (based on partition_filter).
        We should use partition_filter instead of appending to a table, this will ensure the results are always consistent and predictable.
        However, some cases we'll be just appending to a table, for example, when we're appending metrics to a table.
    table_location : str
        Explicit S3/HDFS path for the Delta table (e.g. ``s3a://my-bucket/clean/salesforce/events_case``).
        The writer always sets this path — both on first creation and on subsequent writes — ensuring
        data lands in the expected S3 location rather than the Databricks warehouse default.
    sync_hive : bool, optional
        When True, calls ``sync_trino_table_schema`` from ``sync_metadata`` after
        writing to register or update the table in Trino's Delta catalog.
        Requires ``table_location`` to be set. Defaults to False.
    sync_secondary_catalog : bool, optional
        When True, syncs table DDL to the secondary catalog after writing
        (Glue on Databricks, UC REST on EMR) via
        ``sync_delta_write_to_secondary_catalog``. Requires ``table_location``.
        Defaults to False.
    """

    _require_qualified_table_name(target_table)
    if not _table_exists(spark, target_table):
        logger.info(
            f"Table {target_table} does not exist; creating with partitions {partition_cols or 'none'}"
        )

        parts = target_table.split(".")
        if len(parts) == 2:
            database_name = parts[0]
        else:
            # catalog.database.table -> use catalog.database for CREATE DATABASE
            database_name = ".".join(parts[:-1])
        spark.sql(f"CREATE DATABASE IF NOT EXISTS `{database_name}`")
        writer = df.write.format("delta").mode("overwrite")
        if partition_cols:
            writer = writer.partitionBy(*partition_cols)
        if table_location:
            writer = writer.option("path", table_location)
            logger.info(
                f"m=validate_and_write, msg=Using explicit table location: {table_location}"
            )
        logger.info(f"m=validate_and_write, msg=Trying to create table: {target_table}")
        writer.saveAsTable(target_table)

        if not _table_exists(spark, target_table):
            logger.error(
                f"m=validate_and_write, msg=Table {target_table} was not created"
            )
            raise ValueError(f"Table {target_table} was not created")
        logger.info(
            f"m=validate_and_write, msg=Table {target_table} created successfully"
        )
        _post_write_catalog_sync(
            spark=spark,
            df=df,
            target_table=target_table,
            table_location=table_location,
            partition_cols=partition_cols,
            sync_hive=sync_hive,
            sync_secondary_catalog=sync_secondary_catalog,
        )
        return

    logger.info(f"m=validate_and_write, msg=Writing to table: {target_table}")
    logger.info(f"m=validate_and_write, msg=Partition filter: {partition_filter}")
    logger.info(f"m=validate_and_write, msg=Append mode: {append}")

    if overwrite_schema:
        df = _safe_merge_schema(spark, df, target_table)
    else:
        cols = spark.read.table(target_table).columns
        df = df.select(cols)

    if not append:
        if not partition_filter:
            raise ValueError("partition_filter is required when append=False")

    overwrite_schema_option = "true" if overwrite_schema else "false"
    logger.info(
        f"m=validate_and_write, msg=Overwrite schema option: {overwrite_schema_option}"
    )

    writer = df.write.format("delta").option("mergeSchema", overwrite_schema_option)
    writer = writer.partitionBy(*partition_cols) if partition_cols else writer

    if table_location:
        writer = writer.option("path", table_location)
        logger.info(
            f"m=validate_and_write, msg=Using explicit table location: {table_location}"
        )

    if append:
        writer = writer.mode("append")
    else:
        writer = writer.mode("overwrite")
        writer = writer.option("replaceWhere", partition_filter)
    writer.saveAsTable(target_table)

    _post_write_catalog_sync(
        spark=spark,
        df=df,
        target_table=target_table,
        table_location=table_location,
        partition_cols=partition_cols,
        sync_hive=sync_hive,
        sync_secondary_catalog=sync_secondary_catalog,
    )


def normalize_column_name(col: str) -> str:
    """
    Normalize column names according to the SSt team naming conventions.

    This function standardizes raw field names into snake_case format,
    ensuring consistency across datasets in the clean layer. While the
    function is generic and applies to any source system, it also handles
    common Salesforce naming patterns (e.g., custom field suffixes).

    Transformations applied:
        1. Removes common Salesforce custom field suffix "__c"
        2. Converts CamelCase / PascalCase to snake_case
        3. Converts the result to lowercase
        4. Repositions leading "id_" to a trailing "_id" pattern

    The transformation is deterministic and idempotent, meaning the same
    input will always produce the same output and reapplying the function
    will not further modify an already normalized name.

    Examples:
        AlreadyAskedForApproval__c -> already_asked_for_approval__c
        CaseNumber                 -> case_number
        FS_FID_AlienationStatus__c -> fs_fid_alienation_status__c
        ITBIStatus__c              -> itbi_status
        Id_Account                 -> account_id

    Args:
        col (str): Original column name from any upstream system.

    Returns:
        str: Normalized column name following SSt conventions.
    """
    col = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1_\2", col)
    col = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", col)
    col = col.lower()
    if col.endswith("_id"):
        col = "id_" + col.replace("_id", "")
    return col


def compare_schema_types(left_df: DataFrame, right_df: DataFrame) -> DataFrame:
    """
    Compare the schema types of two DataFrames and return a DataFrame with the comparison results.
    Parameters
    ----------
    left_df : DataFrame
        Left DataFrame to compare.
    right_df : DataFrame
        Right DataFrame to compare.

    Returns
    -------
    DataFrame
        DataFrame with the comparison results.
    """
    left_types = dict(left_df.dtypes)
    right_types = dict(right_df.dtypes)

    all_columns = sorted(set(left_types) | set(right_types))

    rows = [
        (
            col,
            left_types.get(col),
            right_types.get(col),
            left_types.get(col) == right_types.get(col),
        )
        for col in all_columns
    ]

    return left_df.sparkSession.createDataFrame(
        rows, ["column_name", "left_type", "right_type", "same_type"]
    )


def normalize_df_columns(df: DataFrame) -> DataFrame:
    """
    Normalize all DataFrame column names using `normalize_column_name`.

    The function applies column-by-column normalization and validates that
    the resulting names are unique. If normalization causes collisions
    (e.g. two source columns mapping to the same normalized name), a
    ValueError is raised with the conflicting mappings.

    Parameters
    ----------
    df : DataFrame
        Input DataFrame with original column names.

    Returns
    -------
    DataFrame
        DataFrame with normalized column names.

    Raises
    ------
    ValueError
        If normalized column names are duplicated.
    """

    original = df.columns
    new_cols = [normalize_column_name(col) for col in original]
    counter = Counter(new_cols)
    _invalid = [item for item, count in counter.items() if count > 1]
    if _invalid:
        duplicated = {}
        for item in _invalid:
            for idx, _item in enumerate(new_cols):
                if item == _item:
                    duplicated[original[idx]] = new_cols[idx]
        raise ValueError(f"Duplicated cols name at {_invalid} <-> {duplicated}")

    return df.select(
        [F.col(original).alias(new) for original, new in zip(original, new_cols)]
    )


def retrieve_spark_session(job_name: str) -> SparkSession:
    """
    Create or return a Spark session configured for Delta and S3.

    Configuration includes Delta Lake extensions/catalog and S3A settings
    used by SST jobs in this repository.

    Parameters
    ----------
    job_name : str
        Spark application name.

    Returns
    -------
    SparkSession
        Configured Spark session instance.
    """

    return (
        SparkSession.builder.appName(job_name)
        .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
        .config(
            "spark.sql.catalog.spark_catalog",
            "org.apache.spark.sql.delta.catalog.DeltaCatalog",
        )
        .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
        .config(
            "spark.hadoop.fs.s3a.aws.credentials.provider",
            "com.amazonaws.auth.DefaultAWSCredentialsProviderChain",
        )
        .config("spark.hadoop.fs.s3a.path.style.access", "true")
        .config("spark.hadoop.fs.s3a.acl.default", "BucketOwnerFullControl")
        .config("spark.hadoop.fs.s3a.canned.acl", "BucketOwnerFullControl")
        .config("spark.hadoop.fs.s3a.connection.maximum", "480")
        .config("spark.hadoop.fs.s3a.threads.max", "20")
        .config("spark.hadoop.fs.s3a.connection.timeout", "20000")
        .config("spark.hadoop.fs.s3a.socket.timeout", "20000")
        .getOrCreate()
    )


def get_latest_version_from_df(
    df: DataFrame, key_cols: List[str], cols: List[str], sort_col: Union[str, List[str]]
) -> DataFrame:
    """
    Deduplicate a DataFrame by keeping the latest row per key group.

    Groups ``df`` by ``key_cols`` and, for each group, selects the row whose
    ``sort_col`` value is greatest. Non-key columns from that row are returned
    via ``F.max_by``; when ``sort_col`` is a list, ordering uses a struct of those
    columns (lexicographic comparison).

    Parameters
    ----------
    df : DataFrame
        Input DataFrame, typically containing multiple versions of the same
        entity keyed by ``key_cols``.
    key_cols : list of str
        Column names that define the deduplication grain (group-by keys).
    cols : list of str
        Columns to consider when building the output. When empty, all columns
        in ``df`` are used. ``key_cols`` and ``sort_col`` entries are excluded
        from the payload passed to ``max_by`` and re-added from the group keys.
    sort_col : str or list of str
        Column(s) used to rank rows within each group; the row with the
        maximum value is kept. A list enables multi-column tie-breaking.

    Returns
    -------
    DataFrame
        One row per distinct combination of ``key_cols``, with value columns
        taken from the latest version according to ``sort_col``.

    Raises
    ------
    ValueError
        If ``sort_col`` is neither a string nor a list of strings.
    """
    if not cols:
        cols = list(df.columns)

    if isinstance(sort_col, str):
        sort_cols_list = [sort_col]
        order_expr = F.col(sort_col)
    elif isinstance(sort_col, list):
        sort_cols_list = list(sort_col)
        order_expr = F.struct(*[F.col(c) for c in sort_col])
    else:
        raise ValueError(f"Incorrect value for sort_col = {sort_col!r}")

    exclude = set(key_cols) | set(sort_cols_list)
    value_cols = [c for c in cols if c not in exclude]
    cols_expr = F.struct(*[F.col(c) for c in value_cols])

    return (
        df.groupBy(*key_cols)
        .agg(F.max_by(cols_expr, order_expr).alias("latest"))
        .select(*key_cols, "latest.*")
    )


def _complete_dataframe_schema(df: DataFrame, target_schema: List[str]) -> DataFrame:
    """
    Align a DataFrame to an expected column list, filling gaps with nulls.

    For each name in ``target_schema`` that is absent from ``df``, adds a
    column set to SQL NULL (``F.lit(None)``). Then projects ``df`` to exactly
    ``target_schema`` in that order, dropping any extra columns. Intended as a
    shared SST helper (e.g. before ``unionByName``) whenever two DataFrames must
    share the same layout but only one side has all fields populated.

    Parameters
    ----------
    df : DataFrame
        Input DataFrame to normalize.
    target_schema : list of str
        Desired column names and order. Existing columns are kept as-is;
        missing names are added as null.

    Returns
    -------
    DataFrame
        ``df`` with one column per entry in ``target_schema``, in the same order.
        Columns not listed in ``target_schema`` are omitted.

    See Also
    --------
    safe_union_with_target_schema : Completes both sides then unions by name.
    """
    missing_cols = [column for column in target_schema if column not in df.columns]
    for column in missing_cols:
        df = df.withColumn(column, F.lit(None))
    return df.select(*target_schema)


def safe_union_with_target_schema(
    left_df: DataFrame, right_df: DataFrame, target_schema: List[str]
) -> DataFrame:
    """
    Union two DataFrames after aligning both to the same column layout.

    Each input is passed through :func:`_complete_dataframe_schema` so missing
    columns are added as null and column order matches ``target_schema``. The
    result is ``left_df.unionByName(right_df)``, which stacks rows by column
    name instead of position. Use this whenever two SST sources (e.g. a new
    batch and historical rows) must be combined but do not share identical
    schemas.

    Parameters
    ----------
    left_df : DataFrame
        First DataFrame in the union (row order preserved relative to Spark's
        ``unionByName`` semantics).
    right_df : DataFrame
        Second DataFrame in the union.
    target_schema : list of str
        Canonical column names and order applied to both sides before the union.

    Returns
    -------
    DataFrame
        All rows from ``left_df`` followed by all rows from ``right_df``, with
        columns exactly ``target_schema``.

    See Also
    --------
    _complete_dataframe_schema : Adds null columns and projects to ``target_schema``.
    """
    left_df = _complete_dataframe_schema(left_df, target_schema).select(*target_schema)
    right_df = _complete_dataframe_schema(right_df, target_schema).select(
        *target_schema
    )
    return left_df.unionByName(right_df)


@logger(exclude=["spark"], exclude_return=True)
def validate_partition_readability(
    spark, target_table: str, partition_date: str
) -> None:
    (
        spark.read.table(target_table)
        .where(F.col("partition_date") == F.lit(partition_date))
        .limit(1)
        .collect()
    )
