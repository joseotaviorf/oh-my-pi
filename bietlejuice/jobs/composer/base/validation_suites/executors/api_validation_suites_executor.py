from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.base.validation_suites.executors.base_validation_suites_executor import (
    BaseValidationSuitesExecutor,
)

logger = QuintoAndarLogger("APIValidationSuitesExecutor")


class APIValidationSuitesExecutor(BaseValidationSuitesExecutor):
    """
    API Validations Executor
    This executor runs default validations (defined in this class) and custom
     validations (defined in each heir class).

    New default tests to be executed for all api suites should be added
     here.
    """

    def __init__(self, auth):
        """
        :param auth: Authentication dictionary with all API auths stored in Databricks Secrets.
         This is automatically filled by Validation Engine in IntegrationsValidator.run_validation_suites
        """
        super().__init__()
        self.auth = auth

    def _validate_response_dict_success(self, response: dict):
        """
        This method asserts that the dictionary must have a "success" key, a boolean which must be True.
        :param response: Response dictionary returned by the API client.
        """

        assert response["success"]

    def _validate_response_list_not_empty(self, response: list):
        """
        This method asserts that the list must not be empty.
        :param response: Response list returned by the API client.
        """

        assert len(response) > 0
