import xml.etree.ElementTree as ET
import re

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql.functions import col, dayofmonth, month, now, to_timestamp, year
from quintoandar_logger import QuintoAndarLogger

LOGGER = QuintoAndarLogger(__name__)


class DataFrameHandler:
    """
    Encapsulates common operations performed on Spark DataFrames.
    """

    def __init__(self, logger: QuintoAndarLogger):
        """
        Initializes the DataFrameHandler with a logger.

        Args:
            logger (QuintoAndarLogger): The logger instance to be used.
        """
        self.logger = logger

    def read_xml(self, spark: SparkSession, file_path: str) -> DataFrame:
        """
        Reads an XML file and transforms its content into a Spark DataFrame.
        It pre-processes the file to remove control characters and escape invalid
        XML characters (e.g., '&') in text content before parsing to prevent errors.

        Args:
            spark (SparkSession): The active SparkSession.
            file_path (str): The full path to the XML file to be read.

        Returns:
            DataFrame: A Spark DataFrame where each row corresponds to a record in the
                    XML file.

        Raises:
            ValueError: If the XML file is empty or contains no records after parsing.
            xml.etree.ElementTree.ParseError: If there is an error parsing the XML file.
            Exception: For any other unexpected errors.
        """
        try:
            self.logger.info(f"Reading and pre-processing XML file: {file_path}")
            with open(file_path, "r", encoding="utf-8") as f:
                xml_content = f.read()

            # 1. Remove control characters, mirroring REGEXP_REPLACE(..., '[[:cntrl:]]', '')
            # This regex removes characters in the C0 and C1 control blocks, which are invalid in XML 1.0.
            xml_content = re.sub(
                r"[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]", "", xml_content
            )

            # 2. Escape unescaped ampersands that are not part of a valid entity reference.
            # This prevents "not-well formed" parsing errors.
            corrected_content = re.sub(
                r"&(?![a-zA-Z]{2,5};|#\d{2,5};)", "&amp;", xml_content
            )

            root = ET.fromstring(corrected_content)

            rows = []
            for record in root:
                row = {elem.tag: elem.text for elem in record}
                rows.append(row)

            if not rows:
                raise ValueError(
                    f"XML file is empty or contains no records: {file_path}"
                )

            df = spark.createDataFrame(rows)
            return df
        except ET.ParseError as e:
            self.logger.error(f"Error parsing XML file {file_path}: {e}", exc_info=True)
            raise
        except Exception as e:
            self.logger.error(
                f"Unexpected error reading XML file {file_path}: {e}", exc_info=True
            )
            raise

    def rename_columns_to_lower(self, df: DataFrame) -> DataFrame:
        """
        Renames all columns in the input Spark DataFrame to lowercase.

        Args:
            df (DataFrame): The input Spark DataFrame.

        Returns:
            DataFrame: A new Spark DataFrame with all column names converted to lowercase.
        """
        try:
            new_cols = [c.lower() for c in df.columns]
            return df.toDF(*new_cols)
        except Exception as e:
            self.logger.error(
                f"Error renaming columns to lowercase: {e}", exc_info=True
            )
            raise

    def insert_partitions(
        self, df: DataFrame, date_column_to_partition: str, datetime_format: str = None
    ) -> DataFrame:
        """
        Adds 'year', 'month', and 'day' columns to the DataFrame by converting the
        specified string column to a timestamp. A 'ts_load' column with the current
        timestamp is also added.

        Args:
            df (DataFrame): The input Spark DataFrame.
            date_column_to_partition (str): The name of the string column containing
                                            the date information for partitioning.
            datetime_format (str, optional): The format string to use when converting
                                            the date column. Defaults to None.

        Returns:
            DataFrame: A new DataFrame with 'ts_load', 'year', 'month', and 'day' columns.

        Raises:
            ValueError: If all values in the partition column fail to be converted to a valid date.
        """
        df = df.withColumn("ts_load", now())

        if date_column_to_partition not in df.columns:
            self.logger.warning(
                f"Partition column '{date_column_to_partition}' does not exist in the DataFrame."
            )
            return df

        timestamp_col = (
            to_timestamp(col(date_column_to_partition), datetime_format)
            if datetime_format
            else to_timestamp(col(date_column_to_partition))
        )

        df = df.withColumn("year", year(timestamp_col))
        df = df.withColumn("month", month(timestamp_col))
        df = df.withColumn("day", dayofmonth(timestamp_col))

        null_partition_count = df.where(col("year").isNull()).count()
        if null_partition_count > 0:
            total_count = df.count()
            self.logger.warning(
                f"{null_partition_count} out of {total_count} rows have null partition values "
                f"due to failed date conversion on column '{date_column_to_partition}'."
            )
            if null_partition_count == total_count:
                raise ValueError(
                    f"All date conversions failed for partition column '{date_column_to_partition}'. "
                    "Halting job to prevent writing to a null partition."
                )

        return df
