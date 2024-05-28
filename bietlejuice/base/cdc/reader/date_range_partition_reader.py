from pyspark.sql.readwriter import DataFrameReader
from pyspark.sql.dataframe import DataFrame
from datetime import datetime, timedelta


class DateRangePartitionReader:
    """
    Reads data from S3 into a Spark dataframe using a date range. It takes advantage of partitioning to read fewer files than the default reader.
    It is more efficient as long as you're usually reading fewer files than the total number of files in the dataset.

    This is unnecessary for Parquet or Delta. It is especially useful for JSON, however.
    """

    def __init__(
        self,
        dataframe_reader: DataFrameReader,
        dbutils,
        partition_format: str = "year=%Y/month=%m/day=%d",
    ) -> None:
        self.dataframe_reader = dataframe_reader
        self.dbutils = dbutils
        self.partition_format = partition_format

    def load(
        self, base_path: str, start_date: datetime, end_date: datetime, format: str
    ) -> DataFrame:
        """Reads data from S3 into a Spark dataframe using a date range."""

        load_date_paths = self._find_existing_paths(base_path, start_date, end_date)
        if not load_date_paths:
            raise FileNotFoundError(
                f"No data found in {base_path} for the given date range"
            )
        return self.dataframe_reader.option("basePath", base_path).load(
            load_date_paths, format=format
        )

    def _find_existing_paths(
        self, base_path: str, start_date: datetime, end_date: datetime
    ) -> list:
        """Finds existing paths in S3 for a given date range."""

        current_load_date = start_date
        load_date_paths = []
        while current_load_date <= end_date:
            load_path = (
                f"{base_path}/{current_load_date.strftime(self.partition_format)}"
            )
            try:
                self.dbutils.fs.ls(load_path)
                load_date_paths.append(load_path)
            except Exception as e:
                if "java.io.FileNotFoundException" not in str(e):
                    raise e
            current_load_date += timedelta(days=1)

        return load_date_paths
