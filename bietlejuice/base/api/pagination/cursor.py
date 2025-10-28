import logging
import time
from typing import Generator, List, Dict, Any, Optional, Callable, Literal, Protocol

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


class CursorPaginator(BasePaginator):
    """
    Paginator for cursor-based pagination.

    This paginator handles various cursor-based pagination patterns:
    - Point-In-Time (PIT): Used by Elasticsearch, OpenSearch, Greenhouse Audit Log
    - Standard cursor: next_cursor in response body
    - Token-based: next_token, continuation_token, page_token

    Cursors and context identifiers can be sent via:
    - Request headers (common in PIT implementations)
    - Query parameters (common in standard cursor pagination)
    - Mixed (some in headers, some in params)

    Common in APIs like:
    - Greenhouse Audit Log (Point-In-Time)
    - Elasticsearch (Point-In-Time)
    - Google Workspace (page_token)
    - Many modern REST APIs
    """

    def __init__(
        self,
        client: HttpClient,
        endpoint: str,
        initial_params: Optional[Dict[str, Any]] = None,
        initial_headers: Optional[Dict[str, str]] = None,
        cursor_param: str = "cursor",
        cursor_location: Literal["header", "param"] = "param",
        cursor_response_path: str = "next_cursor",
        context_param: Optional[str] = None,
        context_location: Literal["header", "param"] = "header",
        context_response_path: Optional[str] = None,
        page_size_param: Optional[str] = None,
        page_size_location: Literal["header", "param"] = "param",
        page_size: Optional[int] = None,
        extract_results: Optional[
            Callable[[Dict[str, Any]], List[Dict[str, Any]]]
        ] = None,
        extract_pagination_state: Optional[
            Callable[[Dict[str, Any]], Dict[str, Any]]
        ] = None,
        is_last_page: Optional[
            Callable[[Dict[str, Any], List[Dict[str, Any]]], bool]
        ] = None,
        page_delay: Optional[float] = None,
        retry_on_context_expiration: bool = False,
        max_context_retries: int = 3,
        context_expiration_patterns: Optional[List[str]] = None,
    ):
        """
        Initializes the cursor paginator.

        Args:
            client (HttpClient): An HTTP client with a `get` method that accepts
                endpoint, params, and headers arguments.
            endpoint (str): The API endpoint to paginate.
            initial_params (Optional[Dict[str, Any]]): Initial query parameters.
            initial_headers (Optional[Dict[str, str]]): Initial request headers.

            cursor_param (str): Name of the cursor parameter in requests.
                Default: "cursor"
            cursor_location (Literal["header", "param"]): Where to send the cursor.
                Default: "param"
            cursor_response_path (str): Path to extract cursor from response.
                Default: "next_cursor"

            context_param (Optional[str]): Name of the context/session parameter.
                Used in Point-In-Time pagination for maintaining search context.
                Default: None
            context_location (Literal["header", "param"]): Where to send the context.
                Default: "header"
            context_response_path (Optional[str]): Path to extract context from response.
                Default: None

            page_size_param (Optional[str]): Name of the page size parameter.
                Default: None
            page_size_location (Literal["header", "param"]): Where to send page size.
                Default: "param"
            page_size (Optional[int]): Number of items per page.
                Default: None

            extract_results (Optional[Callable]): Function to extract results list from response.
                Signature: (response_json) -> List[Dict]
                Default: tries common patterns
            extract_pagination_state (Optional[Callable]): Custom function to extract pagination state.
                Signature: (response_json) -> Dict[str, Any]
                Should return a dict with keys like "cursor", "context", etc.
                Default: uses cursor_response_path and context_response_path
            is_last_page (Optional[Callable]): Function to determine if this is the last page.
                Signature: (response_json, results) -> bool
                Default: checks if cursor is None or results are empty
            page_delay (Optional[float]): Seconds to wait between page requests.
                Default: None (no delay)
            retry_on_context_expiration (bool): Enable retry logic when context expires.
                Useful for Point-In-Time pagination where the context ID has a limited lifetime.
                Default: False
            max_context_retries (int): Maximum number of retry attempts when context expires.
                Default: 3
            context_expiration_patterns (Optional[List[str]]): Error message patterns to detect
                context expiration. If None, defaults to common patterns like "expired", "Pit_Id".
                Default: None (uses default patterns)
        """
        super().__init__(client)
        self.endpoint = endpoint
        self.initial_params = initial_params or {}
        self.initial_headers = initial_headers or {}

        self.cursor_param = cursor_param
        self.cursor_location = cursor_location
        self.cursor_response_path = cursor_response_path

        self.context_param = context_param
        self.context_location = context_location
        self.context_response_path = context_response_path

        self.page_size_param = page_size_param
        self.page_size_location = page_size_location
        self.page_size = page_size

        self.page_delay = page_delay

        self.retry_on_context_expiration = retry_on_context_expiration
        self.max_context_retries = max_context_retries
        self.context_expiration_patterns = context_expiration_patterns or [
            "expired",
            "Pit_Id",
            "Pit-Id",
            "pit_id",
            "context",
        ]

        self.extract_results = extract_results or self._default_extract_results
        self.extract_pagination_state = (
            extract_pagination_state or self._default_extract_pagination_state
        )
        self.is_last_page = is_last_page or self._default_is_last_page

        context_info = (
            ", context_param=%s (%s)" % (context_param, context_location)
            if context_param
            else ""
        )
        page_size_info = ", page_size=%d" % page_size if page_size else ""
        delay_info = ", %ss delay" % page_delay if page_delay else ""

        LOGGER.debug(
            "Initialized CursorPaginator for endpoint: %s with cursor_param=%s (%s)%s%s%s",
            endpoint,
            cursor_param,
            cursor_location,
            context_info,
            page_size_info,
            delay_info,
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

    def _get_nested_value(self, data: Dict[str, Any], path: str) -> Any:
        """Extract value from nested dictionary using dot notation path."""
        keys = path.split(".")
        value = data
        for key in keys:
            if isinstance(value, dict):
                value = value.get(key)
            else:
                return None
        return value

    def _default_extract_pagination_state(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Default strategy to extract pagination state from response."""
        state = {}

        cursor_value = self._get_nested_value(data, self.cursor_response_path)
        if cursor_value is not None:
            state["cursor"] = cursor_value

        if self.context_response_path:
            context_value = self._get_nested_value(data, self.context_response_path)
            if context_value is not None:
                state["context"] = context_value

        return state

    def _default_is_last_page(
        self, data: Dict[str, Any], results: List[Dict[str, Any]]
    ) -> bool:
        """
        Default strategy to determine if this is the last page.

        The pagination stops if the results list is empty or if there is no
        next cursor provided in the response.
        """
        if not results:
            return True

        next_cursor = self._get_nested_value(data, self.cursor_response_path)

        # Consider last page if cursor is None, empty string, 0, etc.
        if not next_cursor:
            return True

        return False

    def _is_context_expiration_error(self, error: Exception) -> bool:
        """
        Checks if an error indicates context expiration.

        Args:
            error: The exception to check.

        Returns:
            bool: True if the error matches context expiration patterns.
        """
        error_str = str(error)
        return any(pattern in error_str for pattern in self.context_expiration_patterns)

    def _fetch_all_once(self) -> Generator[List[Dict[str, Any]], None, None]:
        """
        Fetches all pages of data from the API.

        Yields:
            List[Dict[str, Any]]: A list of results from each page.
        """
        params = self.initial_params.copy()
        headers = self.initial_headers.copy()

        if self.page_size_param and self.page_size:
            if self.page_size_location == "header":
                headers[self.page_size_param] = str(self.page_size)
            else:
                params[self.page_size_param] = self.page_size

        page_number = 1
        total_records = 0
        pagination_state = {}

        if self.page_size:
            LOGGER.info(
                "Starting cursor-based pagination for endpoint '%s' with page_size=%d",
                self.endpoint,
                self.page_size,
            )
        else:
            LOGGER.info(
                "Starting cursor-based pagination for endpoint '%s'", self.endpoint
            )

        while True:
            try:
                LOGGER.debug("Fetching page %d from '%s'", page_number, self.endpoint)

                response = self.client.get(
                    endpoint=self.endpoint, params=params, headers=headers
                )
                response.raise_for_status()
                data = response.json()

                results = self.extract_results(data)
                total_records += len(results)

                LOGGER.debug("Page %d: Retrieved %d results", page_number, len(results))

                if results:
                    yield results

                pagination_state = self.extract_pagination_state(data)

                if self.is_last_page(data, results):
                    LOGGER.info(
                        "Pagination complete for '%s'. "
                        "Fetched %d total records across %d pages.",
                        self.endpoint,
                        total_records,
                        page_number,
                    )
                    break

                cursor = pagination_state.get("cursor")
                if cursor:
                    if self.cursor_location == "header":
                        headers[self.cursor_param] = str(cursor)
                    else:
                        params[self.cursor_param] = cursor

                if self.context_param:
                    context = pagination_state.get("context")
                    if context:
                        if self.context_location == "header":
                            headers[self.context_param] = str(context)
                        else:
                            params[self.context_param] = context

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

    def fetch_all(self) -> Generator[List[Dict[str, Any]], None, None]:
        """
        Fetches all pages of data from the API with optional retry logic.

        If retry_on_context_expiration is enabled, this method will automatically
        retry pagination from the beginning when a context expiration error is detected.
        This is useful for Point-In-Time pagination where the context ID has a limited lifetime.

        Yields:
            List[Dict[str, Any]]: A list of results from each page.

        Raises:
            Exception: Any exception that occurs during pagination, including context
                expiration errors if max retries are exceeded.
        """
        if not self.retry_on_context_expiration:
            # No retry logic, just delegate to _fetch_all_once
            yield from self._fetch_all_once()
            return

        # Retry logic enabled
        retry_count = 0
        seen_records = 0

        while retry_count <= self.max_context_retries:
            try:
                batch_records = 0
                for page_results in self._fetch_all_once():
                    batch_records += len(page_results)
                    yield page_results

                # Successful completion
                seen_records += batch_records
                LOGGER.info(
                    "Context-aware pagination completed. "
                    "Fetched %d records in this batch (total: %d)",
                    batch_records,
                    seen_records,
                )
                break  # Success, exit retry loop

            except Exception as e:
                if self._is_context_expiration_error(e):
                    retry_count += 1
                    if retry_count > self.max_context_retries:
                        LOGGER.error(
                            "Context expired after %d retries. Total records fetched: %d",
                            self.max_context_retries,
                            seen_records,
                        )
                        raise

                    LOGGER.warning(
                        "Context expired on attempt %d/%d. Restarting pagination with fresh context. "
                        "Records fetched so far: %d",
                        retry_count,
                        self.max_context_retries,
                        seen_records,
                    )
                    # Continue to next iteration to retry with fresh context
                else:
                    # Different error, re-raise immediately
                    raise
