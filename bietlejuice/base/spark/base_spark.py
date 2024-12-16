import re
from urllib.parse import unquote

from pyspark.sql import session, context
from pyspark.conf import SparkConf
from pyspark import SparkContext

from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("base_spark")


class BaseDBUtils:
    @logger(exclude_return=True)
    def get_dbutils(self):
        try:
            from pyspark.dbutils import DBUtils  # type: ignore

            spark = BaseSparkContext.spark
            dbutils = DBUtils(spark)
        except ImportError:
            import IPython  # type: ignore

            dbutils = IPython.get_ipython().user_ns["dbutils"]
        return dbutils

    def discover_partition_values_in_path(
        self, path, dbutils, max_recursive_depth=None
    ):
        """
        Function to discover partition values given a s3 path that has partition folders

        Parameters:
        path: s3 valid path
        dbutils: databricks dbutils object
        max_recursive_depth: how far down to look for partitions recursively. If not set, it will go indefinitely.

        Return:
        List of partition values found in the given path

        Example:
        In a path with the following folders:
            's3://bucket/table/partition1=a/partition2=d',
            's3://bucket/table/partition1=b/partition2=e',
            's3://bucket/table/partition1=c/partition2=f'
        running discover_partition_values_in_path('s3://bucket/table/', dbutils)
        will return [["a", "d"], ["b", "e"], ["c", "f"]]
        """
        if max_recursive_depth == 0:
            return []

        partitions = []
        for directory in self.discover_directories_in_path(path, dbutils):
            partition_format_search_result = re.search(r".+\=(.+)", directory)
            if not partition_format_search_result:
                continue

            partition_value = unquote(partition_format_search_result.group(1))
            next_recursive_depth = (
                max_recursive_depth - 1 if max_recursive_depth is not None else None
            )
            subpartitions = self.discover_partition_values_in_path(
                f"{path}/{directory}", dbutils, max_recursive_depth=next_recursive_depth
            )
            if subpartitions:
                partitions.extend(
                    [[partition_value] + subpartition for subpartition in subpartitions]
                )
            else:
                partitions.append([partition_value])
        return partitions

    def discover_directories_in_path(self, path, dbutils):
        """
        Function to discover directories within a given s3 path

        Parameters:
        path: s3 valid path
        dbutils: databricks dbutils object

        Return:
        List of directory names found in the given path

        Example:
        In a path with the following folders:
            's3://bucket/table/a',
            's3://bucket/table/b',
            's3://bucket/table/c'
        running discover_directories_in_path('s3://bucket/table/', dbutils)
        will return ['a', 'b', 'c']
        """
        directories = [
            directory.name[:-1]
            for directory in dbutils.fs.ls(path)
            if directory.isDir()
        ]
        return directories


class BaseSparkContext:
    conf = SparkConf()
    sc = SparkContext.getOrCreate(conf=conf)
    spark = session.SparkSession(sc)
    sqlContext = context.HiveContext(sc)
