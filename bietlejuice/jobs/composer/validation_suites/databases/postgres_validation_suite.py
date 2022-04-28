from bietlejuice.jobs.composer.base.db import DatabaseEnum
from bietlejuice.jobs.composer.base.validation_suites.executors.database_validation_suites_executor import (
    DatabaseValidationSuitesExecutor,
)
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import PostgresConsumer


class PostgresValidationSuite(DatabaseValidationSuitesExecutor):
    REPOSITORY_CONSUMER_CLASS = PostgresConsumer

    def validate_redshift(self):
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(
            self.auth[DatabaseEnum.DW], SparkClient()
        )
        self._validate_connection(db_consumer)
