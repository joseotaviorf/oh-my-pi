from quintoandar_facebook_api_client.clients import FacebookClient

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.validation_suites.executors.api_validation_suites_executor import (
    APIValidationSuitesExecutor,
)


class MexicoFacebookInsightsValidationSuite(APIValidationSuitesExecutor):
    def __init__(self, auth):
        """
        :param auth: Authentication dictionary with all auths stored in Databricks Secrets.
         This is automatically filled by Validation Engine in IntegrationsValidator.run_validation_suites
        """
        super().__init__(auth)
        self.fb_client = FacebookClient(
            auth[APIEnum.MX_FACEBOOK]["auth"]["access_token"]
        )
