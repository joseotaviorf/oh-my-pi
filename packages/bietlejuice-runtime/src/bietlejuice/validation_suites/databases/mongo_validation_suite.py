from bietlejuice.base.db.database_enum import DatabaseEnum
from bietlejuice.clients.db_clients import MongoClient, SparkClient
from bietlejuice.consumers.db_consumers import MongoConsumer
from bietlejuice.validation_suites.executors.database_validation_suites_executor import (
    DatabaseValidationSuitesExecutor,
)


class MongoValidationSuite(DatabaseValidationSuitesExecutor):
    REPOSITORY_CONSUMER_CLASS = MongoConsumer

    def validate_crm(self):
        conn_config = self.auth[DatabaseEnum.CRM]
        mongo_client = MongoClient(conn_config)
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(mongo_client, SparkClient())
        self._validate_connection(db_consumer)

    def validate_heimdall(self):
        conn_config = self.auth[DatabaseEnum.HEIMDALL]
        mongo_client = MongoClient(conn_config)
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(mongo_client, SparkClient())
        self._validate_connection(db_consumer)
