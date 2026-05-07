import pyspark.sql.functions as F
from pyspark.sql import DataFrame


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
