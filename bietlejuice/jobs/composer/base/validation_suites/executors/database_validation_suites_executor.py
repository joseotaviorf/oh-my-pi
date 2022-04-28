from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.validation_suites.executors.base_validation_suites_executor import (
    BaseValidationSuitesExecutor,
)
from bietlejuice.jobs.composer.consumers.db_consumers import DBConsumer

logger = QuintoAndarLogger("DatabaseValidationSuitesExecutor")


class DatabaseValidationSuitesExecutor(BaseValidationSuitesExecutor):
    """
    Database validations executor.
    This executor runs default validations (defined in this class) and custom
     validations (defined in each heir class).

    New default tests to be executed for all databases suites should be added
     here.
    """

    def __init__(self, auth):
        """
        :param auth: Authentication dictionary with all DB auths stored in Databricks Secrets.
         This is automatically filled by Validation Engine in IntegrationsValidator.run_validation_suites
        """
        super().__init__()
        self.auth = auth

    def _validate_connection(self, db_consumer: DBConsumer):
        """
        Checks if a connection can be established with the database.
        This method is private and is not automatically executed.

         using an arbitrary method.
        """
        df = db_consumer.get_table_names_and_sizes()
        assert df.count() != 0
