import pyspark.sql.functions as F
from pyspark.sql import DataFrame, SparkSession

from bietlejuice.base.sst.core.utils.common import compare_schema_types
from bietlejuice.base.sst.domains.salesforce.api.transform import (
    cast_string_to_boolean,
    remap_struct_expr,
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

        elif right_type == "null" and accept_new_cols:
            expr = F.col(column_name)

        elif left_type == right_type:
            # Avoid casting or other expressions
            expr = F.col(column_name)

        elif right_type.startswith("struct<"):
            expr = remap_struct_expr(column_name, right_type)

        # Missing value or unable to convert it
        elif left_type == "null":
            expr = F.lit(None).cast(right_type)
        elif left_type == "string" and right_type == "boolean":
            expr = cast_string_to_boolean(column_name)

        else:
            expr = F.col(column_name).cast(right_type)

        df = df.withColumn(column_name, expr)
    return df
