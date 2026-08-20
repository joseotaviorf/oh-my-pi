from typing import Any, Dict, List, Optional

import pyspark
import pyspark.sql.functions as F
from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("sst.checks")


@logger(exclude=["df"], exclude_return=False)
def basic_quality_checks(
    df: pyspark.sql.DataFrame,
    required_cols: Optional[List[str]] = None,
    unique_grain: Optional[List[str]] = None,
    fail: bool = True,
) -> Optional[Dict[str, Any]]:
    """
    Run mandatory data quality checks on DataFrames.

    Parameters
    ----------
    df : pyspark.sql.DataFrame
        Input Salesforce CDC DataFrame to be validated.

    required_cols : list[str], optional
        List of column names that must exist in the DataFrame and contain
        no null (or empty, for string) values.

    unique_grain : list[str], optional
        List of column names that must form a unique key in the DataFrame.
        When provided, the function checks for duplicate records based on
        these columns (e.g. ["record_id", "sequence_number"] or
        ["record_id", "commit_number"]).

        This is for grain check, so if your grain is more than one column pass it
        e.g
            [id, sequence] -> One row per id + sequence
            [id] -> One row per ID

    fail : bool, default True
        Controls error-handling behavior:
        - If True, the function raises an exception as soon as a quality
        check fails (fail-fast mode).
        - If False, the function returns a structured report with
        validation metrics and sample failing rows instead of raising.

        NOTE:
        Default to True in production environments.
        Use False only for local debugging or exploratory analysis.

    Returns
    -------
    dict or None
        When fail_or_report=False, returns a dictionary containing quality
        check results such as missing columns, null counts, duplicate counts,
        and sample failing records.
        When fail_or_report=True and all checks pass, returns None.

    Raises
    ------
    ValueError
        If fail=True and any mandatory quality check fails.
    """
    report = {}

    def _fail(msg: str):
        if fail:
            raise ValueError(msg)

    if required_cols:
        # Missing columns check
        missing_cols = [col for col in required_cols if col not in df.columns]
        report["missing_cols"] = missing_cols
        logger.info(f"m=basic_quality_checks, msg=missing_cols check: {missing_cols}")
        if missing_cols:
            _fail(f"Missing required columns: {missing_cols}")

        null_counts = {}
        for col in required_cols:
            count = df.where(F.col(col).isNull()).count()
            if count > 0:
                null_counts[col] = count
        logger.info(f"m=basic_quality_checks, msg=null_counts check: {null_counts}")
        if null_counts:
            report["null_counts"] = null_counts
            _fail(f"Null values found in required columns: {null_counts}")
        else:
            report["null_counts"] = {}

    if unique_grain:
        missing_unique = [c for c in unique_grain if c not in df.columns]
        if missing_unique:
            report["missing_unique_cols"] = missing_unique
            _fail(f"Unique grain columns missing: {missing_unique}")
        else:
            duplicated_rows = (
                df.groupby(*unique_grain)
                .agg(F.count("*").alias("total"))
                .where(F.col("total") > 1)
                .count()
            )
            report["duplicated_count"] = int(duplicated_rows)
            logger.info(
                f"m=basic_quality_checks, msg=duplicated_rows check: {duplicated_rows}"
            )
            if duplicated_rows > 0:
                _fail(
                    f"Duplicated rows found for key {unique_grain}: {duplicated_rows}"
                )

    return report


@logger(exclude=["df"], exclude_return=False)
def validate_non_nullable_columns(
    df: pyspark.sql.DataFrame,
    column_schema: Dict[str, Any],
    fail: bool = True,
) -> Dict[str, int]:
    """
    Validate that columns declared ``is_nullable: false`` contain no null values.

    Reads the per-column ``is_nullable`` flag from a table-spec schema definition
    (``schema.columns`` in ``tables/*.yml``) and checks the actual data. All
    non-nullable columns are counted in a single aggregation pass. Columns
    absent from the DataFrame are skipped (existence is the schema validator's
    concern, not this check's).

    Parameters
    ----------
    df : pyspark.sql.DataFrame
        DataFrame to validate (e.g. the versioned batch before load).
    column_schema : dict
        Mapping of column name to column definition. A column is checked only
        when its definition has ``is_nullable`` explicitly set to False.
    fail : bool, default True
        When True, raises ``ValueError`` if any non-nullable column contains
        nulls. When False, returns the per-column null counts instead.

    Returns
    -------
    dict
        Column name -> null count, only for violating columns. Empty when all
        checks pass.
    """
    df_columns = set(df.columns)
    non_nullable_cols = [
        column_name
        for column_name, column_def in column_schema.items()
        if column_def.get("is_nullable", True) is False and column_name in df_columns
    ]

    if not non_nullable_cols:
        return {}

    null_counts_row = df.select(
        [
            F.sum(F.col(column_name).isNull().cast("int")).alias(column_name)
            for column_name in non_nullable_cols
        ]
    ).collect()[0]

    # sum() over an empty DataFrame returns null; treat it as zero nulls.
    null_counts = {
        column_name: int(null_counts_row[column_name] or 0)
        for column_name in non_nullable_cols
        if (null_counts_row[column_name] or 0) > 0
    }

    logger.info(
        f"m=validate_non_nullable_columns, msg=null_counts check: {null_counts}"
    )
    if null_counts and fail:
        raise ValueError(f"Null values found in non-nullable columns: {null_counts}")

    return null_counts
