from bietlejuice.jobs.composer.base.api.api_enum import APIEnum
from bietlejuice.jobs.composer.base.validation_suites.executors.api_validation_suites_executor import (
    APIValidationSuitesExecutor,
)
from quintoandar_pipedrive_api_client.clients import PipedriveClient
from quintoandar_pipedrive_api_client.constants.endpoint_enum import EndpointEnum


class PortalCasaMineiraPipedriveValidationSuite(APIValidationSuitesExecutor):
    def __init__(self, auth):
        """
        :param auth: Authentication dictionary with all auths stored in Databricks Secrets.
         This is automatically filled by Validation Engine in IntegrationsValidator.run_validation_suites
        """

        super().__init__(auth)
        self.client = PipedriveClient(
            api_token=auth[APIEnum.PIPEDRIVE]["api_token"], attempts=1
        )

    def validate_pipedrive_deals(self):
        self._validate_endpoint(EndpointEnum.PIPEDRIVE_GET_ALL_DEALS.value["path"])

    def validate_pipedrive_stages(self):
        self._validate_endpoint(EndpointEnum.PIPEDRIVE_GET_ALL_STAGES.value["path"])

    def validate_pipedrive_deals_flow(self):
        self._validate_endpoint(
            EndpointEnum.PIPEDRIVE_GET_DEAL_FLOW.value["path"].format(deal_id=1)
        )

    def validate_deals_fields(self):
        self._validate_endpoint(EndpointEnum.PIPEDRIVE_GET_DEAL_FIELDS.value["path"])

    """
    Calls a given endpoint to get a single row, and makes sure the response is a success.
    :param endpoint_path: Path to validate.
    """

    def _validate_endpoint(self, endpoint_path: str):
        params = {"start": 0, "limit": 1, "api_token": self.client.api_token}
        records = self.client.get_records(endpoint_path, params, None)
        self._validate_response_dict_success(records)
