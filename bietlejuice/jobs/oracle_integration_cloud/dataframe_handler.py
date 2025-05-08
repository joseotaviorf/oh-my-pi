import xml.etree.ElementTree as ET

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
        It assumes the XML structure has a root element containing multiple child elements,
        where each child element represents a record and its sub-elements represent
        columns.

        Args:
            spark (SparkSession): The active SparkSession.
            file_path (str): The full path to the XML file to be read.

        Returns:
            DataFrame: A Spark DataFrame where each row corresponds to a record in the
                    XML file, and the columns are derived from the tags of the
                    sub-elements within each record.

        Raises:
            xml.etree.ElementTree.ParseError: If there is an error parsing the XML file
                                            (e.g., malformed XML).
            Exception: For any other unexpected errors encountered during the XML
                    reading or DataFrame creation process.
        """
        try:
            tree = ET.parse(file_path)
            root = tree.getroot()
            rows = []
            for record in root:
                row = {elem.tag: elem.text for elem in record}
                rows.append(row)

            df = spark.createDataFrame(rows)
            return df
        except ET.ParseError as e:
            self.logger.error(f"Error parsing XML file {file_path}: {e}")
            raise
        except Exception as e:
            self.logger.error(f"Unexpected error reading XML file {file_path}: {e}")
            raise

    def rename_columns_to_lower(self, df: DataFrame) -> DataFrame:
        """
        Renames all columns in the input Spark DataFrame to lowercase.

        Args:
            df (DataFrame): The input Spark DataFrame.

        Returns:
            DataFrame: A new Spark DataFrame with all column names converted to lowercase.

        Raises:
            Exception: If any error occurs during the column renaming process.
        """
        try:
            new_cols = [col.lower() for col in df.columns]
            return df.toDF(*new_cols)
        except Exception as e:
            self.logger.error(f"Error renaming columns to lowercase: {e}")
            raise

    def insert_partitions(
        self, df: DataFrame, date_column_to_partition: str, datetime_format: str = None
    ) -> DataFrame:
        """
        Adds 'year', 'month', and 'day' columns to the DataFrame by converting the
        specified string column to a timestamp. If a datetime format is provided,
        it will be used for the conversion; otherwise, Spark's default timestamp
        conversion will be applied. A 'ts_load' column with the current timestamp
        is also added.

        Args:
            df (DataFrame): The input Spark DataFrame.
            date_column_to_partition (str): The name of the string column containing
                                            the date information to be used for
                                            partitioning.
            datetime_format (str, optional): The format string to use when converting
                                            the date column to a timestamp. If None,
                                            Spark's default conversion is used.
                                            Defaults to None.

        Returns:
            DataFrame: A new Spark DataFrame with the added 'ts_load', 'year', 'month',
                    and 'day' columns. If the specified partition column does not
                    exist, a warning is logged, and the original DataFrame is returned
                    with only the 'ts_load' column added.
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

        return df
