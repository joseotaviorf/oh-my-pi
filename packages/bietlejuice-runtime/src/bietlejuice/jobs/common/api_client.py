import logging
import time
from abc import ABC

import requests

from bietlejuice.jobs.common.api_exceptions import (
    InternalServerError,
    RateLimitError,
    raise_for_status,
)

LOGGER = logging.getLogger(__name__)


class BaseAPIClient(ABC):
    """
    An abstract base class for API clients that includes built-in, resilient
    request handling with automatic retries and exponential backoff.
    Authentication is left to the subclass to implement.
    """

    def __init__(
        self, base_url: str, max_retries: int = 3, initial_backoff: float = 2.0
    ):
        """
        Initializes the API client.

        Args:
            base_url (str): The base URL for all API endpoints.
            max_retries (int): The maximum number of times to retry a failed request.
            initial_backoff (float): The initial delay in seconds for the first retry.
        """
        self.base_url = base_url
        self.max_retries = max_retries
        self.backoff_factor = initial_backoff
        self.session = requests.Session()

    def _request(self, method: str, endpoint: str, **kwargs) -> requests.Response:
        """
        Makes a request to the API with built-in retry logic for transient errors.
        """
        url = f"{self.base_url.rstrip('/')}/{endpoint.lstrip('/')}"
        delay = self.backoff_factor

        for attempt in range(self.max_retries + 1):
            try:
                response = self.session.request(method, url, **kwargs)
                raise_for_status(response)
                return response

            except (
                RateLimitError,
                InternalServerError,
                requests.exceptions.ConnectionError,
                requests.exceptions.Timeout,
            ) as e:
                if attempt >= self.max_retries:
                    LOGGER.error(
                        f"Request to '{url}' failed after {self.max_retries + 1} attempts."
                    )
                    raise e

                LOGGER.warning(
                    f"Request to '{url}' failed (Attempt {attempt + 1}/{self.max_retries + 1}). "
                    f"Retrying in {delay:.2f} seconds. Error: {e}"
                )
                time.sleep(delay)
                delay *= 2  # Exponential backoff

    def get(self, endpoint: str, **kwargs) -> requests.Response:
        """Sends a GET request."""
        return self._request("GET", endpoint, **kwargs)

    def post(self, endpoint: str, **kwargs) -> requests.Response:
        """Sends a POST request."""
        return self._request("POST", endpoint, **kwargs)
