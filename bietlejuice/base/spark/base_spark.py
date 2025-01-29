import re
from urllib.parse import unquote

from pyspark.sql import session, context
from pyspark.conf import SparkConf
from pyspark import SparkContext
from py4j.protocol import Py4JError

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


def _get_conf():
    """
    There are two types of clusters in Unity Catalog: SHARED and SINGLE-USER. The former does not allow
    the use of SparkConf constructor, which is used to create a SparkConf object. This function tries to
    create a SparkConf object and returns None if it fails.
    """

    try:
        return SparkConf()
    except Py4JError:
        logger.warning(
            f"SparkConf constructor cannot be used in SHARED clusters in Unity Catalog. Either find an alternative to it, or switch to a single-user cluster. Returning None instead."
        )
        return None


def _get_sql_context(spark, sc):
    """
    There are two types of clusters in Unity Catalog: SHARED and SINGLE-USER. The former does not allow
    the use of HiveContext constructor, which is used to create a sqlContext object. This function tries to
    create a HiveContext object and returns the spark session if it fails.
    """

    try:
        return context.HiveContext(sc)
    except Exception as e:
        # Making sure that the exception is due to the usage in a SHARED UC cluster
        if (
            not hasattr(e, "getErrorClass")
            or e.getErrorClass() != "JVM_ATTRIBUTE_NOT_SUPPORTED"
        ):
            raise e

        logger.warning(
            f"HiveContext constructor cannot be used in SHARED clusters in Unity Catalog. Either find an alternative to it, or switch to a single-user cluster. Returning the spark session instead."
        )
        return spark


class BaseSparkContext:
    conf = _get_conf()
    sc = SparkContext.getOrCreate(conf=conf)
    spark = session.SparkSession(sc)
    sqlContext = _get_sql_context(spark, sc)
