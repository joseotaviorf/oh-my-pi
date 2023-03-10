class DatabaseClientFactory:
    @staticmethod
    def get_client(attribute):

        # The imports need to be inside the function, because this class is imported automatically on __init__.py,
        # and the SparkClient import throws an error depending on the environment
        from bietlejuice.clients.db_clients import PostgresClient
        from bietlejuice.clients.db_clients import AthenaClient
        from bietlejuice.clients.db_clients import SparkClient
        from bietlejuice.clients.db_clients import MongoClient

        DatabaseClientFactory.postgres = PostgresClient
        DatabaseClientFactory.spark = SparkClient
        DatabaseClientFactory.mongo = MongoClient
        DatabaseClientFactory.athena = AthenaClient

        return getattr(DatabaseClientFactory, attribute)
