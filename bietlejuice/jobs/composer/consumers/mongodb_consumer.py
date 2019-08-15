from pymongo import MongoClient

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.consumers.database_consumer import DatabaseConsumer
from bietlejuice.jobs.composer.base.spark import BaseSparkContext

logger = QuintoAndarLogger("MongoDBConsumer")

spark, sc = BaseSparkContext.spark, BaseSparkContext.sc


class MongoDBConsumer(DatabaseConsumer):
    def __init__(self, connection):
        self.connection = connection

    @logger
    def get_table_names_and_sizes(self):
        db = self.connection["db"]
        client = MongoClient(self.connection["uri"])
        collections = [
            {
                "table_name": collection,
                "size": client["tasks"].command("collstats", collection)["size"]
                / 1024
                / 1024,
            }
            for collection in client[db].list_collection_names()
        ]
        df = spark.read.json(sc.parallelize(collections, 1))
        return df

    @logger
    def get_table_schema(self, table_name):
        raise NotImplementedError()

    @logger
    def get_data_from_table(self, table_name):
        db = self.connection["db"]
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
        df = (
            spark.read.format("mongo")
            .option("uri", self.connection["uri"])
            .option("database", db)
            .option("collection", table_name)
            .option("pipeline", query)
            .load()
        )
        return df
