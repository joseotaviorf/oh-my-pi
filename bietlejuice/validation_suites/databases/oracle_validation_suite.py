from bietlejuice.base.db import DatabaseEnum
from bietlejuice.validation_suites.executors.database_validation_suites_executor import (
    DatabaseValidationSuitesExecutor,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.db_consumers import OracleConsumer


class OracleValidationSuite(DatabaseValidationSuitesExecutor):
    REPOSITORY_CONSUMER_CLASS = OracleConsumer

    def validate_cyber(self):
        """
        Validates connection to Cyber database.
        """
        conn_config = self.auth[DatabaseEnum.CYBER]
        db_consumer = self.REPOSITORY_CONSUMER_CLASS(conn_config, SparkClient())
        self._validate_connection(db_consumer)
