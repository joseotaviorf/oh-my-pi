from quintoandar_survicate_api_client.clients import SurvicateClient
from quintoandar_survicate_api_client.consumers import SurvicateConsumer
from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.validation_suites.executors.api_validation_suites_executor import (
    APIValidationSuitesExecutor,
)
from datetime import datetime

"""
The Survicate API Client throws an exception whenever there is any availability problem. Therefore, we don't
need to make any assertions. As long as the methods run to the end, we know there aren't any problems.
"""


class SurvicateValidationSuite(APIValidationSuitesExecutor):
    def __init__(self, auth):
        """
        :param auth: Authentication dictionary with all auths stored in Databricks Secrets.
         This is automatically filled by Validation Engine in IntegrationsValidator.run_validation_suites
        """
        super().__init__(auth)
        self.survicate_client = SurvicateClient(
            api_token=auth[APIEnum.SURVICATE]["api_token"]
        )

    def validate_surveys(self):
        endpoint_enum = "SURVEYS"
        feedback_parameters = None
        optional_parameters = {
            "items_per_page": 100,
            "start": datetime.now().strftime("%Y-%m-%dT23:59:59.000000Z"),
            "end": datetime.now().strftime("%Y-%m-%dT00:00:00.000000Z"),
        }

        survicate_consumer = SurvicateConsumer(self.survicate_client)

        response = survicate_consumer.sync(
            endpoint_enum=endpoint_enum,
            feedback_parameters=feedback_parameters,
            params=optional_parameters,
        )

        self._validate_response_list_not_empty(response)
