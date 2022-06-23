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
        spark = SparkContext.getOrCreate()
        setting = spark.getConf().get("spark.master")
        if "local" in setting:
            from pyspark.dbutils import DBUtils

            logger.info("m=get_db_utils, msg=returning local dbutils reference")
            return DBUtils(spark.sparkContext)

        logger.info("m=get_db_utils, msg=dbutils already available")

    @logger(exclude_return=True)
    def discover_partition_values_in_path(self, path, dbutils):
        """
        Function to discover partition values given a s3 path that has partition folders

        Parameters:
        path: s3 valid path
        dbutils: databricks dbutils object

        Return:
        List of partition values found in the given path

        Example:
        In a path with the following folders:
            's3://bucket/table/partition=a',
            's3://bucket/table/partition=b',
            's3://bucket/table/partition=c'
        running discover_partition_values_in_path('s3://bucket/table/', dbutils)
        will return ['a', 'b', 'c']
        """
        partitions = [
            unquote(directory.split("=")[1])
            for directory in self.discover_directories_in_path(path, dbutils)
            # filter only directories with names in partition format
            if re.search(r".+\=.+", directory)
        ]
        return partitions

    @logger(exclude_return=True)
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
