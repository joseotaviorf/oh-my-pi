from bietlejuice.jobs.composer.base.db import DatabaseEnum
from bietlejuice.jobs.composer.base.validation_suites.executors.database_validation_suites_executor import (
    DatabaseValidationSuitesExecutor,
)
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import MySqlConsumer


class MySQLValidationSuite(DatabaseValidationSuitesExecutor):
    REPOSITORY_CONSUMER_CLASS = MySqlConsumer

    def validate_arquivo_confidencial(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.ARQUIVO_CONFIDENCIAL], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_ebdb(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.EBDB], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_kill_queue(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.KILL_QUEUE], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_legaut(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.LEGAUT], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_vans(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.VANS], SparkClient()
        )
        self._validate_connection(db_consumer)

    def validate_wallstreet(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.WALL_STREET], SparkClient()
        )
        self._validate_connection(db_consumer)
