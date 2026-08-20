"""S3 I/O for the SFMC file-based (SFTP) ingestion.

SFMC delivers each tracking extract as a plain, uncompressed CSV file whose S3
key is fully determined by the delivery type, the team name and the date —
``{de_type}_{team_name}_{partition_date}.csv``. Because the key is fixed, the
raw pipeline builds the exact path instead of listing the bucket to discover
it, so no S3 SDK is needed anywhere: Spark's own reader does the I/O.

Uncompressed is deliberate too: Spark reads a plain CSV as a *splittable*
source and parallelizes it across tasks, while a gzip (or tar.gz) member is
non-splittable and would be parsed by a single task no matter how large it is.
"""

from typing import Optional

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql.utils import AnalysisException
from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("sst.domains.sfmc.io")

PATH_NOT_FOUND_MARKER = "Path does not exist"


def to_spark_path(s3_path: str) -> str:
    """Return ``s3_path`` with the ``s3a://`` scheme Spark is configured for.

    Every table location in this repo uses ``s3a://``, but a caller may still
    hand in ``s3://`` (e.g. copied from an S3 console URL), so this is applied
    defensively before every read.
    """
    if s3_path.startswith("s3://"):
        return f"s3a://{s3_path[len('s3://') :]}"
    return s3_path


def build_csv_path(
    source_prefix: str, de_type: str, team_name: str, partition_date: str
) -> str:
    """Build the exact path SFMC delivers for one extract on one day.

    SFMC's file naming is fixed: ``{de_type}_{team_name}_{partition_date}.csv``,
    e.g. ``send_growth_2026-08-05.csv``. ``partition_date`` is used verbatim
    (``YYYY-MM-DD``), since that already matches the delivered format.

    Parameters
    ----------
    source_prefix : str
        Prefix holding the delivered files,
        e.g. ``s3a://5a-datalake-prod/raw/sfmc/tracking-data``.
    de_type : str
        Delivery type segment, e.g. ``send``, ``return``, ``template``.
    team_name : str
        Team name segment.
    partition_date : str
        Date segment, ``YYYY-MM-DD``.

    Returns
    -------
    str
        Full path of the delivered CSV.
    """
    file_name = f"{de_type}_{team_name}_{partition_date}.csv"
    return f"{source_prefix.rstrip('/')}/{file_name}"


def read_csv(
    spark: SparkSession,
    csv_path: str,
    delimiter: str = ",",
    encoding: str = "UTF-8",
) -> DataFrame:
    """Read one delivered CSV into a DataFrame, letting Spark infer column types.

    ``multiLine`` plus the double-quote escape handle the RFC-4180 quoting SFMC
    uses for text fields that embed newlines. Note that ``multiLine`` makes the
    file non-splittable: correctness first, since a quoted newline read without
    it silently splits one row into two. If a large extract ever makes this the
    bottleneck, and its fields are known to be newline-free, dropping the option
    restores the parallel read.

    Parameters
    ----------
    spark : SparkSession
    csv_path : str
        ``s3://`` or ``s3a://`` path of a single CSV.
    delimiter : str, optional
        Field separator; SFMC extracts are comma or tab delimited.
    encoding : str, optional
        File encoding.

    Returns
    -------
    DataFrame
        Header-derived column names, inferred column types.

    Raises
    ------
    pyspark.sql.utils.AnalysisException
        The path does not exist. Use :func:`read_csv_if_exists` when a missing
        delivery is expected and should be skipped instead of failing.
    """
    return (
        spark.read.option("header", "true")
        .option("inferSchema", "true")
        .option("delimiter", delimiter)
        .option("encoding", encoding)
        .option("multiLine", "true")
        .option("escape", '"')
        .csv(to_spark_path(csv_path))
    )


def read_csv_if_exists(
    spark: SparkSession,
    csv_path: str,
    delimiter: str = ",",
    encoding: str = "UTF-8",
) -> Optional[DataFrame]:
    """Read a delivered CSV, or return ``None`` when SFMC has not dropped it yet.

    Spark's CSV reader is eager about schema inference: it samples the file
    (and raises if the path is missing) the moment ``read.csv`` is called,
    rather than only when the DataFrame is later actioned. That is the only
    Spark-native signal available for "does this object exist" without an S3
    SDK call, so a missing-path ``AnalysisException`` is treated as "not
    delivered yet"; any other error still propagates.
    """
    try:
        return read_csv(spark, csv_path, delimiter=delimiter, encoding=encoding)
    except AnalysisException as error:
        if PATH_NOT_FOUND_MARKER not in str(error):
            raise
        logger.info(
            "m=read_csv_if_exists, msg=No file delivered at this path, "
            f"csv_path={csv_path}"
        )
        return None
