import logging
from typing import Generator, Dict, Any, Optional, List

from .base import BasePaginator
from bietlejuice.base.api.common.client import BaseAPIClient


LOGGER = logging.getLogger(__name__)


class HeaderLinkPaginator(BasePaginator):
    """
    A paginator for APIs that use 'Link' headers for pagination, following
    RFC 5988. Common in APIs like GitHub's.
    """

    def __init__(
        self,
        client: BaseAPIClient,
        endpoint: str,
        params: Optional[Dict[str, Any]] = None,
    ):
        """
        Initializes the paginator.

        Args:
            client (BaseAPIClient): An instance of BaseAPIClient.
            endpoint (str): The initial API endpoint for the request.
            params (Optional[Dict[str, Any]]): A dictionary of query
                                               parameters for the initial
                                               request.
        """
        super().__init__(client)
        self.next_url = f"{self.client.base_url.rstrip('/')}/{endpoint.lstrip('/')}"
        self.params = params or {}

    def _parse_link_header(self, headers: Dict[str, str]) -> Optional[str]:
        """
        Parses the 'Link' header to find the URL for the 'next' page.
        """
        link_header = headers.get("Link")
        if not link_header:
            return None

        links = link_header.split(", ")
        for link in links:
            parts = link.split("; ")
            if len(parts) == 2 and 'rel="next"' in parts[1]:
                return parts[0].strip("<>")
        return None

    def fetch_all(self) -> Generator[List[Dict[str, Any]], None, None]:
        """
        Fetches all pages of data from the API endpoint.
        Yields a list of items for each page.
        """
        is_first_request = True
        while self.next_url:
            # Only send params on the first request, as subsequent URLs from the Link header will contain them.
            current_params = self.params if is_first_request else {}

            response = self.client.session.get(
                self.next_url, params=current_params, timeout=self.client.timeout
            )
            self.client._handle_response(response)
            is_first_request = False

            data = response.json()
            if isinstance(data, list):
                yield data
            elif (
                isinstance(data, dict)
                and "items" in data
                and isinstance(data["items"], list)
            ):
                yield data["items"]
            else:
                LOGGER.warning(
                    "The API response is not a list of items or a dict with an 'items' key. "
                    "Stopping pagination."
                )
                break

            self.next_url = self._parse_link_header(response.headers)
            # Clear params after the first request
            self.params = {}
