from bietlejuice.jobs.composer.clients.db_clients import PostgresClient
from bietlejuice.jobs.composer.clients.db_clients import AthenaClient
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.clients.db_clients import MongoClient


class DatabaseClientFactory:
    postgres = PostgresClient
    spark = SparkClient
    mongo = MongoClient
    athena = AthenaClient

    @staticmethod
    def get_client(attribute):
        return getattr(DatabaseClientFactory, attribute)
