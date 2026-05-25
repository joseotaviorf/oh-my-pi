from pyspark.sql import DataFrame, SparkSession, Window
from pyspark.sql import functions as F

from bietlejuice.base.sst.core.utils.common import compare_schema_types
from bietlejuice.base.sst.domains.salesforce.api.transform import (
    cast_string_to_boolean,
    parse_struct_column,
)


def nullify_fields_on_delete(
    df: DataFrame, non_null_cols: list[str] | None = None
) -> DataFrame:
    """
    Null out payload columns on DELETE rows while keeping key/metadata columns.

    For each row where ``event_type == "DELETE"``, every column except those
    listed in ``non_null_cols`` is set to SQL NULL. Other rows are unchanged.
    Column order is preserved.

    Parameters
    ----------
    df : DataFrame
        Input frame; must include an ``event_type`` column.
    non_null_cols : list of str, optional
        Column names to leave untouched on DELETE (e.g. ids, partition keys).
        Defaults to an empty list (all columns nullified on DELETE).

    Returns
    -------
    DataFrame
        Same schema as ``df`` with DELETE-row nulling applied.
    """
    if non_null_cols is None:
        non_null_cols = []

    null_cols = set(df.columns) - set(non_null_cols)
    return df.select(
        *[
            (
                F.when(F.col("event_type") == "DELETE", F.lit(None))
                .otherwise(F.col(col))
                .alias(col)
                if col in null_cols
                else F.col(col)
            )
            for col in df.columns  # So we don't change column order
        ]
    )


def get_chunks(data: list, max_size: int) -> list:
    """
    Partition a list into contiguous slices of at most ``max_size`` elements.

    Parameters
    ----------
    data : list
        Sequence to chunk (length may be smaller than ``max_size``).
    max_size : int
        Maximum length of each chunk; must be positive for useful output.

    Returns
    -------
    list
        List of slices, e.g. ``get_chunks([1,2,3,4], 2) -> [[1,2],[3,4]]``.
    """
    return [data[i : i + max_size] for i in range(0, len(data), max_size)]


def get_versioning_df(
    input_df: DataFrame,
    context_col_name: str,
    event_col_name: str,
    event_ts_col_name: str,
    commit_number_col_name: str = None,
) -> DataFrame:
    """
    Add temporal versioning columns to ``input_df`` per business context.

    Rows are ordered by ``event_ts_col_name`` (ascending) within each
    ``context_col_name`` partition. Each row gets an ``effective_timestamp`` equal
    to its event time, ``expired_timestamp`` as the next event's time in that
    context (or a sentinel high date when there is no successor), and
    ``is_current`` when there is no next event. ``_created_at`` is propagated as
    the first non-null value in the partition (ordered by event time);
    ``_last_updated_at`` is set to the current timestamp.

    Parameters
    ----------
    input_df : DataFrame
        Source dataframe; must include ``context_col_name``, ``event_ts_col_name``,
        ``_created_at``, and optionally ``commit_number_col_name``(for salesforce it is required) when that tie-breaker
        is used.
    context_col_name : str
        Column that identifies the entity or grain for which versions are computed
        (window partition key).
    event_col_name : str
        Name of the event column (logged for observability; not used in the transform).
    event_ts_col_name : str
        Column with the event effective time used to order versions and compute
        ``effective_timestamp`` / ``expired_timestamp``.
    commit_number_col_name : str, optional
        When set, breaks ties on identical event timestamps by ordering descending on
        this column within each ``context_col_name`` partition.

    Returns
    -------
    DataFrame
        ``input_df`` with added columns ``effective_timestamp``, ``expired_timestamp``,
        ``is_current``, ``_created_at`` (filled from partition), and ``_last_updated_at``.
    """

    high_date = F.to_timestamp(F.lit("9999-12-31 23:59:59"))

    window_effective_ts = (
        Window.partitionBy(context_col_name).orderBy(
            F.col(event_ts_col_name).asc(), F.col(commit_number_col_name).desc()
        )
        if commit_number_col_name
        else Window.partitionBy(context_col_name).orderBy(
            F.col(event_ts_col_name).asc()
        )
    )
    next_effective_ts = F.lead(F.col(event_ts_col_name)).over(window_effective_ts)

    now = F.current_timestamp()
    window_pipeline_cols = Window.partitionBy(context_col_name).orderBy(
        event_ts_col_name
    )

    return (
        input_df.withColumn("_effective_timestamp", F.col(event_ts_col_name))
        .withColumn("_expired_timestamp", F.coalesce(next_effective_ts, high_date))
        .withColumn("_is_current", next_effective_ts.isNull())
        .withColumn(
            "_created_at",
            F.first("_created_at", ignorenulls=True).over(window_pipeline_cols),
        )
        .withColumn("_last_updated_at", now)
    )


def get_rows_to_update(
    spark: SparkSession, table_name: str, update_df: DataFrame, context_col_name: str
) -> DataFrame:
    """
    Select current target rows that must participate in an SCD Type 2 refresh.

    Used by core model pipelines when merging a new batch into an existing Delta
    table. The function reads the target, keeps only rows with
    ``_is_current == True``, and inner-joins on ``context_col_name`` with the
    distinct business keys present in ``update_df``. The result is the slice of
    persisted history that overlaps the incoming load and may need to be
    expired or re-versioned (for example, set ``_is_current`` to false, union
    with the new events, then run :func:`get_versioning_df`).

    Parameters
    ----------
    spark : SparkSession
        Active Spark session used to read ``table_name``.
    table_name : str
        Fully qualified target table (``schema.table``) with SCD metadata
        columns, including ``_is_current``.
    update_df : DataFrame
        Incoming batch for the current load; must contain ``context_col_name``.
    context_col_name : str
        Business key or grain column shared by target and update (e.g.
        ``id_case``); join key for matching rows to refresh.

    Returns
    -------
    DataFrame
        Target rows that are currently active (``_is_current`` true) for every
        distinct ``context_col_name`` value in ``update_df``. Schema matches the
        target table projection used in the join (all target columns).
    """
    target_historical_df = spark.table(table_name).where((F.col("_is_current") == True))
    unique_rows = update_df.select(context_col_name).distinct()
    return target_historical_df.join(unique_rows, on=context_col_name, how="inner")


def apply_schema_remaps(
    spark: SparkSession,
    df: DataFrame,
    target_table: str | DataFrame,
    accept_new_cols: bool = False,
) -> DataFrame:
    """
    Since API and CDC may have different types, we're making sure we're matching the types
    This can be used for clean events (it should be normalized first) or for RAW (no normalization needed)
    """

    if isinstance(target_table, str):
        target_table = spark.table(target_table)

    # This return a list of tuple with column_name, type_left, type_right and if type is matching
    type_mistmatches = compare_schema_types(df, target_table).collect()

    for col in type_mistmatches:
        column_name = col["column_name"]
        left_type = col["left_type"]
        right_type = col["right_type"]

        if column_name not in df.columns or not accept_new_cols:
            continue

        elif right_type is None and accept_new_cols:
            expr = F.col(column_name)

        elif left_type == right_type:
            # Avoid casting or other expressions
            expr = F.col(column_name)

        elif right_type.startswith("struct<"):
            expr = parse_struct_column(left_type, column_name, right_type)

        # Missing value or unable to convert it
        elif left_type is None:
            expr = F.lit(None).cast(right_type)
        elif left_type == "string" and right_type == "boolean":
            expr = cast_string_to_boolean(column_name)

        else:
            expr = F.col(column_name).cast(right_type)

        df = df.withColumn(column_name, expr)
    return df
