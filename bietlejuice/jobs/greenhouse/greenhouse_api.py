import json
import time
import requests
import base64

from bietlejuice.base.spark import BaseDBUtils
from quintoandar_logger import QuintoAndarLogger

LOGGER = QuintoAndarLogger(__name__)


class GreenhouseAPI:
    """
    A client to interact with the Greenhouse Harvest API, handling
    authentication, pagination, and robust rate limiting.
    """

    _API_BASE_URL = "https://harvest.greenhouse.io/v1/"
    _PAGE_SIZE = 500
    _MAX_RETRIES = 5

    def __init__(self, job_args: dict):
        """
        Initializes the API client using parameters from the job arguments.

        Args:
            job_args (dict): A dictionary containing job parameters such as
                             the endpoint, dates, and filters.
        """
        self.endpoint = job_args.get("endpoint")
        self.load_start_date = job_args.get("load_start_date")
        self.load_end_date = job_args.get("load_end_date")
        self.base_filters = job_args.get("base_filters", {})
        self._page_size = int(job_args.get("page_size", self._PAGE_SIZE))

        self._api_key = self._get_secrets()
        self._auth_headers = self._create_auth_headers()

    def _get_secrets(self) -> str:
        """Securely retrieves the API key using Databricks Utilities."""
        try:
            base_dbutils = BaseDBUtils()
            dbutils = base_dbutils.get_dbutils()
            raw_secret = dbutils.secrets.get(scope="PEOPLE", key="GREENHOUSE_API")
            secret = json.loads(raw_secret)
            api_key = secret.get("api_key")
            if not api_key:
                raise ValueError("The 'api_key' was not found in the secret.")
            return api_key
        except Exception as e:
            LOGGER.error(f"Failed to retrieve Greenhouse secrets: {e}", exc_info=True)
            raise

    def _create_auth_headers(self) -> dict:
        """Creates the authentication headers for the Greenhouse API (Basic Auth)."""
        credentials = f"{self._api_key}:".encode("utf-8")
        encoded_credentials = base64.b64encode(credentials).decode("utf-8")
        return {
            "Authorization": f"Basic {encoded_credentials}",
            "Accept": "application/json",
        }

    def _make_request_with_rate_limit_handling(
        self, url: str, params: dict | None = None
    ) -> requests.Response:
        """
        Executes a GET request to the API, handling rate limiting reactively.

        Raises:
            requests.exceptions.RequestException: If the request fails after all retries.
        """
        retries = 0
        while retries < self._MAX_RETRIES:
            try:
                response = requests.get(url, headers=self._auth_headers, params=params)

                if response.ok:
                    return response

                if response.status_code == 429:
                    retry_after = response.headers.get("Retry-After")
                    if retry_after:
                        wait_time = int(retry_after)
                        LOGGER.warning(
                            f"Rate limit exceeded. Waiting {wait_time}s (Retry-After)."
                        )
                    else:
                        reset_timestamp = response.headers.get("X-RateLimit-Reset")
                        if reset_timestamp:
                            wait_time = max(0, int(reset_timestamp) - int(time.time()))
                            LOGGER.warning(
                                f"Rate limit exceeded. Waiting {wait_time}s (X-RateLimit-Reset)."
                            )
                        else:
                            wait_time = 10  # Fallback
                            LOGGER.warning(
                                f"Rate limit exceeded. Wait headers not found. Waiting {wait_time}s."
                            )

                    time.sleep(wait_time + 0.1)
                    retries += 1
                    LOGGER.info(
                        f"Retrying request... (Attempt {retries}/{self._MAX_RETRIES})"
                    )
                    continue

                response.raise_for_status()

            except requests.exceptions.RequestException as e:
                LOGGER.error(
                    f"HTTP error during request to '{url}': {e}", exc_info=True
                )
                raise

        raise requests.exceptions.RequestException(
            f"Request to '{url}' failed after {self._MAX_RETRIES} retries due to rate limiting."
        )

    @staticmethod
    def _parse_next_link_from_header(headers: dict) -> str | None:
        """Parses the 'Link' header from the response to find the next page URL."""
        link_header = headers.get("Link")
        if not link_header:
            return None

        links = link_header.split(",")
        for link in links:
            if 'rel="next"' in link:
                start = link.find("<") + 1
                end = link.find(">")
                return link[start:end]
        return None

    def _fetch_paginated_data(self, params: dict) -> list:
        """Fetches all paginated data, using the rate-limit-aware request method."""
        processed_params = params.copy()
        processed_params["per_page"] = self._page_size

        for key, value in processed_params.items():
            if value == "load_start_date" and self.load_start_date:
                processed_params[key] = self.load_start_date.strftime(
                    "%Y-%m-%dT%H:%M:%SZ"
                )
            elif value == "load_end_date" and self.load_end_date:
                processed_params[key] = self.load_end_date.strftime(
                    "%Y-%m-%dT%H:%M:%SZ"
                )

        all_results = []
        next_page_url = f"{self._API_BASE_URL}{self.endpoint}"
        is_first_request = True
        page_count = 1

        while next_page_url:
            current_params = processed_params if is_first_request else None
            try:
                LOGGER.info(f"Fetching page {page_count} from '{self.endpoint}'...")
                response = self._make_request_with_rate_limit_handling(
                    url=next_page_url, params=current_params
                )
                is_first_request = False

                page_data = response.json()
                if page_data:
                    all_results.extend(page_data)

                next_page_url = self._parse_next_link_from_header(response.headers)
                if next_page_url:
                    page_count += 1

            except json.JSONDecodeError as e:
                LOGGER.error(
                    f"Failed to decode JSON from response: {e}. Response text: {response.text}",
                    exc_info=True,
                )
                raise

        LOGGER.info(
            f"Fetch complete for '{self.endpoint}'. Total of {len(all_results)} records in {page_count} pages."
        )
        return all_results

    def get_all_paginated_results(self) -> list:
        """Fetches all results from the configured endpoint."""
        if not self.endpoint:
            LOGGER.error("API endpoint not defined in job arguments.")
            raise ValueError("API endpoint is not defined.")

        return self._fetch_paginated_data(self.base_filters)
