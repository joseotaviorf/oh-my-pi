import logging
from typing import Optional, Union
from datetime import datetime, date

import requests
from bietlejuice.base.api.common.exceptions import (
    APIException,
    BadRequestError,
    NotFoundError,
    RateLimitError,
)
from bietlejuice.base.api.rate_limit.header_adapter import HeaderRateLimitAdapter

LOGGER = logging.getLogger(__name__)


class BaseAPIClient:
    """
    A base client for interacting with REST APIs, including handling for
    retries, rate limiting, and standardized error responses.
    """

    def __init__(
        self,
        base_url: str,
        common_headers: Optional[dict] = None,
        timeout: int = 30,
        max_retries: int = 3,
        min_remaining_threshold: int = 5,
    ):
        self.base_url = base_url
        self.session = requests.Session()
        self.session.headers.update(common_headers or {})

        # Set up retry and rate limiting adapters
        retry_strategy = requests.packages.urllib3.util.retry.Retry(
            total=max_retries,
            status_forcelist=[429, 500, 502, 503, 504],
            allowed_methods=["HEAD", "GET", "OPTIONS", "POST"],
            backoff_factor=1,
        )
        adapter = HeaderRateLimitAdapter(
            max_retries=retry_strategy, min_remaining_threshold=min_remaining_threshold
        )
        self.session.mount("https://", adapter)
        self.session.mount("http://", adapter)

        self.timeout = timeout

    def _handle_response(self, response: requests.Response):
        """Checks for errors in the response and raises appropriate exceptions."""
        if response.status_code == 400:
            raise BadRequestError(f"Bad Request: {response.text}")
        if response.status_code == 404:
            raise NotFoundError(f"Not Found: {response.text}")
        if response.status_code == 429:
            raise RateLimitError("Rate limit exceeded")

        response.raise_for_status()

    @staticmethod
    def format_iso_timestamp(
        date_value: Union[str, datetime, date],
        default_time_suffix: str = "T00:00:00.000Z",
    ) -> str:
        """
        Formats a date value into an ISO-8601 timestamp string.

        This is a common requirement for many REST APIs that expect timestamps
        in ISO-8601 format with timezone information.

        Args:
            date_value: The date to format. Can be:
                - str: Date string (YYYY-MM-DD or already formatted timestamp)
                - datetime: Python datetime object
                - date: Python date object
            default_time_suffix: Time suffix to append if date_value is date-only.
                Default: "T00:00:00.000Z" (midnight UTC)

        Returns:
            str: ISO-8601 formatted timestamp string ending with 'Z' (UTC).
        """
        if isinstance(date_value, str):
            if "T" in date_value or " " in date_value:
                date_str = date_value.replace(" ", "T")
                if not date_str.endswith("Z"):
                    date_str += "Z"
                return date_str
            else:
                return f"{date_value}{default_time_suffix}"
        elif isinstance(date_value, datetime):
            return date_value.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
        else:
            # date object (no time component)
            date_part = date_value.strftime("%Y-%m-%d")
            return f"{date_part}{default_time_suffix}"

    def get(
        self,
        endpoint: str,
        params: Optional[dict] = None,
        headers: Optional[dict] = None,
    ) -> requests.Response:
        """Sends a GET request to the specified endpoint."""
        url = f"{self.base_url.rstrip('/')}/{endpoint.lstrip('/')}"
        try:
            response = self.session.get(
                url, params=params, headers=headers, timeout=self.timeout
            )
            self._handle_response(response)
            return response
        except requests.RequestException as e:
            LOGGER.error(f"HTTP request to {url} failed: {e}")
            raise APIException(f"Request to {endpoint} failed") from e

    def post(
        self,
        endpoint: str,
        params: Optional[dict] = None,
        json: Optional[dict] = None,
        headers: Optional[dict] = None,
    ) -> requests.Response:
        """Sends a POST request with an optional JSON body to the specified endpoint."""
        url = f"{self.base_url.rstrip('/')}/{endpoint.lstrip('/')}"
        try:
            response = self.session.post(
                url,
                params=params,
                json=json,
                headers=headers,
                timeout=self.timeout,
            )
            self._handle_response(response)
            return response
        except requests.RequestException as e:
            LOGGER.error(f"HTTP request to {url} failed: {e}")
            raise APIException(f"Request to {endpoint} failed") from e
