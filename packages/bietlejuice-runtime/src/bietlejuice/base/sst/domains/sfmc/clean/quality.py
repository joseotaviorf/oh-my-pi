"""Contract checks and dead-letter routing for the SFMC clean layer.

The clean layer enforces a small contract on every delivered row: it must carry
an ``event_id`` and a ``source_data_extension``, and the pair must be unique
within the day. A row that breaks any of these is not silently dropped and not
allowed into the clean table either — it is routed to a dead-letter (DLQ)
table, stamped with when it was rejected and with one flag per check it failed,
so the rejects stay inspectable and countable.

Three checks, three flag columns:

- ``failed_missing_event_id``
- ``failed_missing_source_data_extension``
- ``failed_duplicate_grain``
"""

from functools import reduce
from typing import List, Tuple

import pyspark.sql.functions as F
from pyspark.sql import Column, DataFrame, Window
from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("sst.domains.sfmc.clean.quality")

EVENT_ID_COL = "event_id"
SOURCE_DATA_EXTENSION_COL = "source_data_extension"

# The grain the clean table is expected to be unique on.
GRAIN_COLS = [EVENT_ID_COL, SOURCE_DATA_EXTENSION_COL]

# What ``normalize_column_name`` produces for a delivered ``EventID`` /
# ``event_id`` header: the SST convention moves a trailing ``_id`` to the front.
NORMALIZED_EVENT_ID_COL = "id_event"

MISSING_EVENT_ID_CHECK = "failed_missing_event_id"
MISSING_SOURCE_DATA_EXTENSION_CHECK = "failed_missing_source_data_extension"
DUPLICATE_GRAIN_CHECK = "failed_duplicate_grain"

CHECK_COLS = [
    MISSING_EVENT_ID_CHECK,
    MISSING_SOURCE_DATA_EXTENSION_CHECK,
    DUPLICATE_GRAIN_CHECK,
]

TS_DLQ_COL = "ts_dlq"


def _is_missing(col_name: str) -> Column:
    """A value is missing when it is null or blank once trimmed.

    A CSV yields both shapes for "no value": an unquoted empty field reads as
    null, a quoted one (``""``) reads as an empty string. Casting to string
    first makes this work for numeric columns too.
    """
    column = F.col(col_name)
    return column.isNull() | (F.trim(column.cast("string")) == "")


def conform_required_columns(df: DataFrame) -> DataFrame:
    """Bring the contract columns into the shape the checks expect.

    Raw lands the delivered headers verbatim, so the clean layer snake_cases
    them first (``normalize_df_columns``), which turns a delivered ``EventID``
    into ``id_event``. The clean contract is spelled ``event_id``, so it is
    renamed back here — the rename is skipped when the frame already carries an
    ``event_id``, so a delivery that uses that spelling directly is left alone.

    A contract column SFMC did not deliver at all is added as null. That keeps
    the checks runnable — every row then fails that check and lands in the DLQ,
    which is visible in the metric — instead of the job dying on an unresolved
    column reference.
    """
    if NORMALIZED_EVENT_ID_COL in df.columns and EVENT_ID_COL not in df.columns:
        df = df.withColumnRenamed(NORMALIZED_EVENT_ID_COL, EVENT_ID_COL)

    for required_col in GRAIN_COLS:
        if required_col not in df.columns:
            logger.warning(
                "m=conform_required_columns, msg=Contract column absent from the "
                f"delivered file, adding it as null, column={required_col}"
            )
            df = df.withColumn(required_col, F.lit(None).cast("string"))

    return df


def flag_quality_checks(df: DataFrame) -> DataFrame:
    """Add one boolean column per contract check.

    Every flag is a non-null boolean, so callers can filter on them directly.
    A row may fail more than one check, and then carries more than one flag.
    """
    missing_event_id = _is_missing(EVENT_ID_COL)
    missing_source_data_extension = _is_missing(SOURCE_DATA_EXTENSION_COL)

    # Uniqueness is only meaningful for rows that actually carry a grain: two
    # rows both missing event_id are not "the same event twice", they are two
    # invalid rows, and counting them as duplicates would inflate the metric
    # and hide the real reason they were rejected.
    has_grain = (~missing_event_id) & (~missing_source_data_extension)
    grain_occurrences = F.count("*").over(Window.partitionBy(*GRAIN_COLS))

    return (
        df.withColumn(MISSING_EVENT_ID_CHECK, missing_event_id)
        .withColumn(MISSING_SOURCE_DATA_EXTENSION_CHECK, missing_source_data_extension)
        .withColumn(DUPLICATE_GRAIN_CHECK, has_grain & (grain_occurrences > 1))
    )


def split_checked_rows(
    flagged_df: DataFrame, dlq_timestamp: str, check_cols: List[str] = None
) -> Tuple[DataFrame, DataFrame]:
    """Split a flagged frame into the rows to publish and the rows to reject.

    Accepted rows are those that failed no check; they come back without the
    flag columns, since those carry no information once every one of them is
    false. Rejected rows keep their flags — that is the record of *why* they
    were rejected — and gain ``ts_dlq``.

    Every copy of a duplicated grain is rejected. Nothing arbitrary is kept:
    with no tie-breaker in the extract there is no basis for calling one of
    them the real row, and picking one would be non-deterministic anyway.

    Parameters
    ----------
    flagged_df : DataFrame
        Output of :func:`flag_quality_checks`.
    dlq_timestamp : str
        When these rows were rejected, ``yyyy-MM-dd HH:mm:ss``.
    check_cols : list of str, optional
        Flag columns to consider; defaults to every contract check.

    Returns
    -------
    tuple
        ``(accepted_df, rejected_df)``.
    """
    check_cols = check_cols or CHECK_COLS
    failed_any_check = reduce(
        lambda left, right: left | right, [F.col(col) for col in check_cols]
    )

    accepted_df = flagged_df.where(~failed_any_check).drop(*check_cols)
    rejected_df = flagged_df.where(failed_any_check).withColumn(
        TS_DLQ_COL, F.lit(dlq_timestamp)
    )

    return accepted_df, rejected_df
