from pymongo import MongoClient
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import BaseSparkContext
from bietlejuice.jobs.composer.consumers.db_consumers.db_consumer import DBConsumer

logger = QuintoAndarLogger("MongoConsumer")

spark, sc = BaseSparkContext.spark, BaseSparkContext.sc  # todo: remove this


class MongoConsumer(DBConsumer):
    """
    This class is deprecated at the moment. If you want to use it, please, check the
    other database consumers (e.g. PostgresConsumer) and refactor it. Try to remove
    the dependency on the external MongoClient class and only use the SparkClient
    class to read data from Mongo if you want to return Spark DataFrames in the
    inherited methods (defined by the interface DBConsumer). Also, try to favor
    dependency injection and avoid spark code in this class.
    """

    def __init__(self, conn_config):
        self.connection = conn_config

    @logger
    def get_table_names_and_sizes(self):
        db = self.connection["db"]
        client = MongoClient(self.connection["uri"])
        mb_size = 1048576

        collections = [
            {
                "table_name": collection,
                "size": client[db].command("collstats", collection)["size"] / mb_size,
            }
            for collection in client[db].list_collection_names()
        ]
        df = spark.read.json(sc.parallelize(collections, 1))  # todo: remove this
        return df

    @logger
    def get_table_schema(self, table_name):
        raise NotImplementedError()

    @logger
    def get_data_from_table(self, table_name):
        db = self.connection["db"]
        # todo: remove this
        df = (
            spark.read.format("mongo")
            .option("uri", self.connection["uri"])
            .option("database", db)
            .option("collection", table_name)
            .load()
        )
        return df

    @logger
    def get_data_from_table_in_parallel(self, table_name, concurrency):
        raise NotImplementedError()

    @logger
    def get_data_from_query(self, query, table_name):
        db = self.connection["db"]
        # todo: remove this
        df = (
            spark.read.format("mongo")
            .option("uri", self.connection["uri"])
            .option("database", db)
            .option("collection", table_name)
            .option("pipeline", query)
            .load()
        )
        return df
