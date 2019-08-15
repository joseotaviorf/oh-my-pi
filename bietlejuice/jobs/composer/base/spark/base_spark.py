import re
from urllib.parse import unquote

from pyspark.sql import session, context
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
        return [
            unquote(file_info.name.split("=")[1][:-1])
            for file_info in dbutils.fs.ls(path)
            # filter only directories with names in partition format
            if file_info.isDir() and re.search(r".+\=.+", file_info.name)
        ]


class BaseSparkContext:
    sc = SparkContext.getOrCreate()
    spark = session.SparkSession(sc)
    sqlContext = context.HiveContext(sc)
