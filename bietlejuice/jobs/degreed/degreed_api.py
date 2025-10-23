import json
import time
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from bietlejuice.base.spark import BaseDBUtils
from quintoandar_logger import QuintoAndarLogger

LOGGER = QuintoAndarLogger(__name__)


class DegreedAPI:
    """
    A class to interact with the Degreed API, handling authentication
    (with token caching per scope) and fetching paginated data based on dynamic filters.
    """

    _TOKEN_URLS = {
        "PROD": "https://degreed.com/oauth/token",
        "FORNO": "https://betatest.degreed.com/oauth/token",
    }
    _API_BASE_URLS = {
        "PROD": "https://api.degreed.com/api/v2/",
        "FORNO": "https://api.betatest.degreed.com/api/v2/",
    }
    _REQUEST_DELAY_SECONDS = 0.5
    _MAX_RETRIES = 5
    _BACKOFF_FACTOR = 2

    def __init__(self, job_args: dict):
        """
        Initializes the API client using parameters parsed from the job arguments.

        Args:
            job_args (dict): A dictionary containing job parameters like environment,
                             scope, filters, and table_name (endpoint).
        """
        self.environment = job_args.get("environment", "PROD").upper()
        if self.environment not in self._TOKEN_URLS:
            LOGGER.error(
                f"Invalid environment provided: '{self.environment}'. Must be 'PROD' or 'FORNO'."
            )
            raise ValueError(
                f"Invalid environment '{self.environment}'. Use 'PROD' or 'FORNO'."
            )

        self.base_url = self._API_BASE_URLS[self.environment]
        self.endpoint = job_args.get("table_name").replace("_", "-")
        self.scope = job_args.get("scope")
        self.load_start_date = job_args.get("load_start_date")
        self.load_end_date = job_args.get("load_end_date")
        self.base_filters = job_args.get("base_filters", {})

        self._client_id, self._client_secret = self._get_secrets()
        self._access_tokens = {}
        self._session = self._create_session_with_retries()

    def _create_session_with_retries(self) -> requests.Session:
        """
        Creates a requests session with automatic retry logic for transient errors.

        Returns:
            requests.Session: A configured session with retry capabilities.
        """
        session = requests.Session()

        retry_strategy = Retry(
            total=self._MAX_RETRIES,
            backoff_factor=self._BACKOFF_FACTOR,
            status_forcelist=[500, 502, 503, 504],
            allowed_methods=["GET", "POST"],
            raise_on_status=False,
        )

        adapter = HTTPAdapter(max_retries=retry_strategy)
        session.mount("http://", adapter)
        session.mount("https://", adapter)

        return session

    def _get_secrets(self):
        """
        Securely retrieves API credentials using Databricks Utilities.

        Returns:
            tuple: A tuple containing the CLIENT_ID and CLIENT_SECRET.
        """
        try:
            base_dbutils = BaseDBUtils()
            dbutils = base_dbutils.get_dbutils()
            raw_secret = dbutils.secrets.get(scope="people", key="DEGREED_API")
            secret = json.loads(raw_secret)
            client_id = secret.get("CLIENT_ID")
            client_secret = secret.get("CLIENT_SECRET")
            if not client_id or not client_secret:
                raise ValueError("CLIENT_ID or CLIENT_SECRET not found in the secret.")
            return client_id, client_secret
        except Exception as e:
            LOGGER.error(f"Failed to retrieve secrets: {e}", exc_info=True)
            raise

    def _fetch_new_token(self, scope: str) -> str:
        """
        Fetches a new access token from the Degreed API for a specific scope.

        Args:
            scope (str): The permission scope for the token.

        Returns:
            str: The access token.
        """
        url = self._TOKEN_URLS[self.environment]
        headers = {"Content-Type": "application/x-www-form-urlencoded"}
        data = {
            "grant_type": "client_credentials",
            "client_id": self._client_id,
            "client_secret": self._client_secret,
            "scope": scope,
        }

        try:
            response = self._session.post(url, headers=headers, data=data)
            response.raise_for_status()
            response_json = response.json()
            access_token = response_json.get("access_token")
            if not access_token:
                LOGGER.error(
                    f"Failed to obtain access token, 'access_token' key not in response. Response: {response_json}"
                )
                raise Exception(f"Failed to obtain access token for scope '{scope}'.")

            return access_token
        except requests.exceptions.RequestException as e:
            LOGGER.error(
                f"HTTP error while fetching token for scope '{scope}': {e}",
                exc_info=True,
            )
            raise

    def _fetch_paginated_data_for_params(
        self, params: dict, auth_headers: dict
    ) -> list:
        """
        Fetches all paginated data for a given set of URL parameters.
        Dynamically replaces date placeholders with formatted values.

        Args:
            params (dict): The URL query parameters to be used for the request.
                           May contain the values "load_start_date" and "load_end_date".
            auth_headers (dict): The authentication headers containing the token.

        Returns:
            list: A list containing all results from all pages.
        """
        processed_params = params.copy()

        for key, value in processed_params.items():
            if value == "load_start_date":
                processed_params[key] = (
                    self.load_start_date.strftime("%Y-%m-%d")
                    if self.load_start_date
                    else None
                )

            elif value == "load_end_date":
                processed_params[key] = (
                    self.load_end_date.strftime("%Y-%m-%d")
                    if self.load_end_date
                    else None
                )

        results_for_params = []
        next_page_url = f"{self.base_url}{self.endpoint}"
        is_first_request = True
        page_count = 1

        while next_page_url:
            current_params = processed_params if is_first_request else None

            try:
                LOGGER.info(
                    f"Fetching page {page_count} from {next_page_url} with params: {current_params}"
                )

                response = self._session.get(
                    next_page_url,
                    headers=auth_headers,
                    params=current_params,
                    timeout=60,
                )

                LOGGER.info(
                    f"Response status: {response.status_code}, "
                    f"headers: {dict(response.headers)}, "
                    f"elapsed: {response.elapsed.total_seconds()}s"
                )

                if response.status_code >= 400:
                    error_msg = (
                        f"API returned status {response.status_code} on page {page_count}. "
                        f"URL: {next_page_url}, Response: {response.text[:500]}"
                    )
                    LOGGER.error(error_msg)
                    response.raise_for_status()

                is_first_request = False
                json_response = response.json()
                page_data = json_response.get("data", [])

                if page_data:
                    results_for_params.extend(page_data)
                    LOGGER.info(f"Page {page_count} returned {len(page_data)} records")
                else:
                    LOGGER.warning(f"Page {page_count} returned no data")

                next_page_url = json_response.get("links", {}).get("next")
                if next_page_url:
                    page_count += 1
                    time.sleep(self._REQUEST_DELAY_SECONDS)

            except requests.exceptions.HTTPError as e:
                error_details = {
                    "status_code": response.status_code if response else "N/A",
                    "response_body": response.text[:1000] if response else "N/A",
                    "url": next_page_url,
                    "page": page_count,
                    "params": current_params,
                }
                LOGGER.error(
                    f"HTTP error during pagination: {e}. Details: {error_details}",
                    exc_info=True,
                )

                if response and response.status_code >= 500:
                    LOGGER.error(
                        f"Server error {response.status_code} persisted after {self._MAX_RETRIES} retries. "
                        f"This may indicate an issue with the Degreed API. "
                        f"Consider: 1) Checking Degreed API status, "
                        f"2) Reducing the limit parameter, "
                        f"3) Contacting Degreed support if the issue persists."
                    )
                raise
            except requests.exceptions.Timeout as e:
                LOGGER.error(
                    f"Request timeout on page {page_count} after 60 seconds: {e}",
                    exc_info=True,
                )
                raise
            except requests.exceptions.RequestException as e:
                LOGGER.error(
                    f"Request error during pagination on page {page_count}: {e}",
                    exc_info=True,
                )
                raise
            except json.JSONDecodeError as e:
                response_text = response.text if response else "No response"
                LOGGER.error(
                    f"Failed to decode JSON from response on page {page_count}: {e}. "
                    f"Response text: {response_text[:1000]}",
                    exc_info=True,
                )
                raise

        return results_for_params

    def get_all_paginated_results(self) -> list:
        """
        Fetches all results from the configured endpoint.

        Returns:
            list: A list containing all results from all pages and all filter combinations.
        """
        if not self.scope:
            LOGGER.error("API scope is not defined in job arguments.")
            raise ValueError(
                "API scope is not defined. Please provide it in the job arguments."
            )
        if not self.endpoint:
            LOGGER.error("API endpoint (table_name) is not defined in job arguments.")
            raise ValueError(
                "API endpoint (table_name) is not defined. Please provide it in the job arguments."
            )

        all_results = []
        scope = self.scope
        if scope not in self._access_tokens:
            self._access_tokens[scope] = self._fetch_new_token(scope)

        access_token = self._access_tokens[scope]
        auth_headers = {
            "Authorization": f"Bearer {access_token}",
            "Accept": "application/json",
        }

        params = self.base_filters.copy()
        all_results.extend(self._fetch_paginated_data_for_params(params, auth_headers))

        return all_results
