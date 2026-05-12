import logging
import time
from typing import Dict

import requests
from requests.models import Response

from bietlejuice.base.api.rate_limit.base import BaseRateLimitAdapter

LOGGER = logging.getLogger(__name__)


class HeaderRateLimitAdapter(BaseRateLimitAdapter):
    """
    An HTTPAdapter to handle API rate limiting based on headers.

    This adapter manages API limits by:
    1. Proactively pausing requests when a rate limit threshold is reached.
    2. Parsing rate limit reset times, supporting both Unix timestamps and
       relative seconds.
    3. Reactively handling HTTP 429 responses, waiting for the duration
       specified in the 'Retry-After' header.
    """

    def __init__(
        self,
        min_remaining_threshold: int = 5,
        limit_header: str = "X-RateLimit-Limit",
        remaining_header: str = "X-RateLimit-Remaining",
        reset_header: str = "X-RateLimit-Reset",
        unix_timestamp_threshold: int = 100000,
        wait_buffer_seconds: float = 0.1,
        *args,
        **kwargs,
    ):
        """
        Initializes the rate limit adapter.

        Args:
            min_remaining_threshold (int): Pauses requests when the number of
                remaining calls reaches this value.
            limit_header (str): Name of the header indicating the total
                request limit.
            remaining_header (str): Name of the header indicating the
                remaining requests.
            reset_header (str): Name of the header indicating when the time
                window resets.
            unix_timestamp_threshold (int): The threshold to distinguish between
                a relative reset time (in seconds) and an absolute Unix timestamp.
            wait_buffer_seconds (float): A small buffer added to the wait time
                to ensure the rate limit window has passed.
        """
        super().__init__(*args, **kwargs)
        self.min_remaining_threshold = min_remaining_threshold
        self.limit_header = limit_header
        self.remaining_header = remaining_header
        self.reset_header = reset_header
        self.unix_timestamp_threshold = unix_timestamp_threshold
        self.wait_buffer_seconds = wait_buffer_seconds

        self.rate_limit_remaining: int = min_remaining_threshold + 1
        self.rate_limit_reset_time: float = 0.0

    def _update_rate_limit_from_headers(self, headers: Dict[str, str]):
        """Updates the internal rate limit state from the response headers."""
        try:
            remaining = headers.get(self.remaining_header)
            reset = headers.get(self.reset_header)

            if remaining is not None:
                self.rate_limit_remaining = int(remaining)

            if reset is not None:
                reset_value = float(reset)
                if reset_value < self.unix_timestamp_threshold:
                    self.rate_limit_reset_time = time.time() + reset_value
                else:
                    self.rate_limit_reset_time = reset_value

            LOGGER.debug(
                f"Rate limit status: "
                f"Remaining={self.rate_limit_remaining}, "
                f"Resets at={time.ctime(self.rate_limit_reset_time)}"
            )
        except (ValueError, TypeError) as e:
            LOGGER.warning(f"Could not parse rate limit headers: {e}")

    def _wait_if_needed(self):
        """Pauses execution if the request limit is nearing its end."""
        if self.rate_limit_remaining <= self.min_remaining_threshold:
            current_time = time.time()
            wait_duration = self.rate_limit_reset_time - current_time

            if wait_duration > 0:
                LOGGER.warning(
                    f"Rate limit threshold reached ({self.rate_limit_remaining} remaining). "
                    f"Waiting for {wait_duration:.2f} seconds."
                )
                time.sleep(wait_duration + self.wait_buffer_seconds)

    def send(self, request: requests.PreparedRequest, **kwargs) -> Response:
        """
        Sends the request, applying waiting logic before and, if necessary,
        after the request is sent.
        """
        self._wait_if_needed()

        response = super().send(request, **kwargs)

        self._update_rate_limit_from_headers(response.headers)

        if response.status_code == 429:
            retry_after = response.headers.get("Retry-After")
            if retry_after:
                try:
                    wait_time = int(retry_after)
                    LOGGER.error(
                        f"Received status 429. API requested a wait of {wait_time} seconds. Retrying..."
                    )
                    time.sleep(wait_time)
                    return self.send(request, **kwargs)
                except (ValueError, TypeError):
                    LOGGER.error(
                        "Received status 429 with an invalid 'Retry-After' header."
                    )
            else:
                LOGGER.error(
                    "Received status 429 (Too Many Requests), but 'Retry-After' header was not found."
                )

        return response
