import logging
from typing import Optional

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
    ):
        self.base_url = base_url
        self.session = requests.Session()
        self.session.headers.update(common_headers or {})

        # Set up retry and rate limiting adapters
        retry_strategy = requests.packages.urllib3.util.retry.Retry(
            total=max_retries,
            status_forcelist=[429, 500, 502, 503, 504],
            allowed_methods=["HEAD", "GET", "OPTIONS"],
            backoff_factor=1,
        )
        adapter = HeaderRateLimitAdapter(max_retries=retry_strategy)
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

    def get(self, endpoint: str, params: Optional[dict] = None) -> requests.Response:
        """Sends a GET request to the specified endpoint."""
        url = f"{self.base_url.rstrip('/')}/{endpoint.lstrip('/')}"
        try:
            response = self.session.get(url, params=params, timeout=self.timeout)
            self._handle_response(response)
            return response
        except requests.RequestException as e:
            LOGGER.error(f"HTTP request to {url} failed: {e}")
            raise APIException(f"Request to {endpoint} failed") from e
