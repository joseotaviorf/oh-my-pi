from bietlejuice.jobs.composer.base.db import DatabaseEnum
from bietlejuice.jobs.composer.base.validation_suites.executors.database_validation_suites_executor import (
    DatabaseValidationSuitesExecutor,
)
from bietlejuice.jobs.composer.clients.db_clients import SparkClient, MongoClient
from bietlejuice.jobs.composer.consumers.db_consumers import MongoConsumer


class MongoValidationSuite(DatabaseValidationSuitesExecutor):
    REPOSITORY_CONSUMER_CLASS = MongoConsumer

    def validate_cidade_alerta(self):
        conn_config = self.auth[DatabaseEnum.CIDADE_ALERTA]
        mongo_client = MongoClient(conn_config)
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(mongo_client, SparkClient())
        self._validate_connection(db_consumer)
