import base64
import json

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.spark.base_spark import BaseDBUtils
from bietlejuice.jobs.common.api_client import BaseAPIClient
from bietlejuice.jobs.common.api_exceptions import APIException

LOGGER = QuintoAndarLogger(__name__)


class OICprocessingAPI(BaseAPIClient):
    """
    A class to interact with the OIC Data Lake processing API.
    It handles authentication and sending processing requests.
    """

    _API_URLS = {
        "PROD": "https://oic-prod-grpzlpocngfq-gr.integration.sa-saopaulo-1.ocp.oraclecloud.com/ic/api/integration/v1/flows/rest/REPROCESSARDATALAKEEXPORT/1.0/",
        "FORNO": "https://oic-dev-grpzlpocngfq-gr.integration.sa-saopaulo-1.ocp.oraclecloud.com/ic/api/integration/v1/flows/rest/REPROCESSARDATALAKEEXPORT/1.0/",
    }

    def __init__(self, environment: str = "PROD"):
        """
        Initializes the API client.
        """
        self.environment = environment.upper()
        api_url = self._API_URLS.get(self.environment)
        if not api_url:
            raise ValueError(
                f"Invalid environment provided: '{environment}'. Use 'PROD' or 'FORNO'."
            )

        super().__init__(base_url=api_url)

        self._username, self._password = self._get_secrets()
        self._prepare_auth_header()

    def _get_secrets(self) -> tuple[str, str]:
        """
        Securely retrieves API credentials using Databricks Utilities,
        handling case-insensitive keys for username and password.

        Returns:
            tuple: A tuple containing the username and password.
        """
        try:
            base_dbutils = BaseDBUtils()
            dbutils = base_dbutils.get_dbutils()
            raw_secret = dbutils.secrets.get(scope="PEOPLE", key="HCM_SFTP")
            secret = json.loads(raw_secret)
            secret_lower = {k.lower(): v for k, v in secret.items()}
            username = secret_lower.get("username")
            password = secret_lower.get("key")
            if not username or not password:
                LOGGER.error(
                    "'username' or 'key' not found in 'HCM_SFTP' secret (case-insensitive search)."
                )
                raise ValueError("Username or Key not found in the secret.")
            return username, password
        except Exception as e:
            LOGGER.error(f"Failed to retrieve secrets: {e}", exc_info=True)
            raise

    def _prepare_auth_header(self) -> None:
        """
        Prepares the Basic authentication header and applies it to the session.
        """
        auth_string = f"{self._username}:{self._password}"
        base64_auth_string = base64.b64encode(auth_string.encode("utf-8")).decode(
            "utf-8"
        )
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Basic {base64_auth_string}",
        }
        self.session.headers.update(headers)

    def send_process_request(self, report_name: str) -> dict:
        """
        Triggers the processing flow for a specific report using the resilient
        post method from the base class.

        Args:
            report_name (str): The name of the report to be reprocessed (without the 'RM_' prefix).

        Returns:
            dict: The API response in JSON format on success.

        Raises:
            Exception: If the API returns a business logic error (returnStatus: "E").
            requests.exceptions.RequestException: For HTTP or network-level errors.
        """
        payload = {
            "displayName": f"RM_{report_name}",
            "absolutePath": f"/QuintoAndar/REPORTS_DATALAKE/RM_{report_name}.xdo",
        }

        response = self.post(endpoint="", data=json.dumps(payload), timeout=600)

        response_json = response.json() if response.text else {}

        if response_json.get("returnStatus") == "E":
            error_message = response_json.get(
                "returnMessage", "Unknown API business error"
            )
            LOGGER.error(f"OIC API returned a failure status: {error_message}")
            raise APIException(error_message, response_text=json.dumps(response_json))

        LOGGER.info(f"OIC API response received: {response_json}")
        return response_json
