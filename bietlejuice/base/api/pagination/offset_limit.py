import logging
import time
from typing import Generator, List, Dict, Any, Optional, Callable, Protocol

from bietlejuice.base.api.pagination.base import BasePaginator

LOGGER = logging.getLogger(__name__)


class HttpClient(Protocol):
    """Protocol defining the interface required for HTTP clients."""

    def get(
        self,
        endpoint: str,
        params: Optional[Dict[str, Any]] = None,
        headers: Optional[Dict[str, str]] = None,
    ) -> Any:
        """Make a GET request to the API."""
        ...


class OffsetLimitPaginator(BasePaginator):
    """
    Paginator for offset/limit-based pagination.

    This paginator handles APIs that use offset and limit parameters for pagination.
    The offset represents the starting position in the result set, and limit represents
    the number of items to return per page.

    Common in APIs like:
    - Oracle HCM (HR System)
    - LinkedIn API
    - Many REST APIs with traditional pagination
    """

    def __init__(
        self,
        client: HttpClient,
        endpoint: str,
        initial_params: Optional[Dict[str, Any]] = None,
        initial_headers: Optional[Dict[str, str]] = None,
        limit_param: str = "limit",
        offset_param: str = "offset",
        page_size: int = 100,
        extract_results: Optional[
            Callable[[Dict[str, Any]], List[Dict[str, Any]]]
        ] = None,
        is_last_page: Optional[
            Callable[[Dict[str, Any], List[Dict[str, Any]]], bool]
        ] = None,
        page_delay: Optional[float] = None,
    ):
        """
        Initializes the offset/limit paginator.

        Args:
            client (HttpClient): An HTTP client with a `get` method that accepts
                endpoint, params, and headers arguments.
            endpoint (str): The API endpoint to paginate.
            initial_params (Optional[Dict[str, Any]]): Initial query parameters.
            initial_headers (Optional[Dict[str, str]]): Initial request headers.

            limit_param (str): Name of the limit parameter in requests.
                Default: "limit"
            offset_param (str): Name of the offset parameter in requests.
                Default: "offset"
            page_size (int): Number of items per page.
                Default: 100

            extract_results (Optional[Callable]): Function to extract results list from response.
                Signature: (response_json) -> List[Dict]
                Default: tries common patterns
            is_last_page (Optional[Callable]): Function to determine if this is the last page.
                Signature: (response_json, results) -> bool
                Default: checks if results list is empty or has fewer items than page_size
            page_delay (Optional[float]): Seconds to wait between page requests.
                Default: None (no delay)
        """
        super().__init__(client)
        self.endpoint = endpoint
        self.initial_params = initial_params or {}
        self.initial_headers = initial_headers or {}

        self.limit_param = limit_param
        self.offset_param = offset_param
        self.page_size = page_size

        self.page_delay = page_delay

        self.extract_results = extract_results or self._default_extract_results
        self.is_last_page = is_last_page or self._default_is_last_page

        LOGGER.debug(
            "Initialized OffsetLimitPaginator for endpoint: %s with "
            "limit_param=%s, offset_param=%s, page_size=%d%s",
            endpoint,
            limit_param,
            offset_param,
            page_size,
            f", {page_delay}s delay" if page_delay else "",
        )

    def _default_extract_results(self, data: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Default strategy to extract results from various response formats."""
        if isinstance(data, list):
            return data
        if isinstance(data, dict):
            for field in ["results", "items", "data", "records", "entries"]:
                if field in data and isinstance(data[field], list):
                    return data[field]
        return []

    def _default_is_last_page(
        self, data: Dict[str, Any], results: List[Dict[str, Any]]
    ) -> bool:
        """
        Default strategy to determine if this is the last page.

        The pagination stops if the results list is empty or if it has fewer
        items than the page_size, indicating there are no more pages.
        """
        if not results:
            return True

        if len(results) < self.page_size:
            return True

        return False

    def fetch_all(self) -> Generator[List[Dict[str, Any]], None, None]:
        """
        Fetches all pages of data from the API using offset/limit pagination.

        Yields:
            List[Dict[str, Any]]: A list of results from each page.
        """
        params = self.initial_params.copy()
        headers = self.initial_headers.copy()

        params[self.limit_param] = self.page_size
        params[self.offset_param] = 0

        page_number = 1
        total_records = 0
        offset = 0

        LOGGER.info(
            "Starting offset/limit pagination for endpoint '%s' with page_size=%d",
            self.endpoint,
            self.page_size,
        )

        while True:
            try:
                params[self.offset_param] = offset
                params[self.limit_param] = self.page_size

                LOGGER.debug(
                    "Fetching page %d from '%s' with %s=%d, %s=%d",
                    page_number,
                    self.endpoint,
                    self.offset_param,
                    offset,
                    self.limit_param,
                    self.page_size,
                )

                response = self.client.get(
                    endpoint=self.endpoint, params=params, headers=headers
                )
                data = response.json()

                results = self.extract_results(data)
                total_records += len(results)

                LOGGER.debug("Page %d: Retrieved %d results", page_number, len(results))

                if results:
                    yield results

                if self.is_last_page(data, results):
                    LOGGER.info(
                        "Pagination complete for '%s'. "
                        "Fetched %d total records across %d pages.",
                        self.endpoint,
                        total_records,
                        page_number,
                    )
                    break

                offset += self.page_size
                page_number += 1

                if self.page_delay and self.page_delay > 0:
                    LOGGER.debug(
                        "Waiting %ss before fetching next page (rate limit delay)",
                        self.page_delay,
                    )
                    time.sleep(self.page_delay)

            except Exception as e:
                LOGGER.error(
                    "Error fetching page %d from '%s': %s",
                    page_number,
                    self.endpoint,
                    e,
                    exc_info=True,
                )
                raise
