import logging
import time
from typing import Any, Callable, Dict, Generator, List, Optional

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.api_ingestion_enums import (
    HttpMethodEnum,
)
from bietlejuice.base.api.pagination.base import BasePaginator
from bietlejuice.base.api.pagination.offset_limit import HttpClient

LOGGER = logging.getLogger(__name__)


def _get_by_dot_path(data: Any, dot_path: str) -> Any:
    """Returns the value at a dot-separated key path in nested dicts, or None."""
    value = data
    for key in dot_path.split("."):
        if not isinstance(value, dict):
            return None
        value = value.get(key)
    return value


class PagePerPagePaginator(BasePaginator):
    """
    Paginator for 1-based page index plus page size (e.g. ``page`` / ``per_page`` query params).

    With ``http_method="post"``, the page and page size are sent inside ``json_body``
    instead of the query string.

    Stops when the page count at ``total_pages_path`` (or ``metadata.totalPages``) is reached,
    when a page returns fewer rows than ``page_size``, or when a page is empty.
    """

    def __init__(
        self,
        client: HttpClient,
        endpoint: str,
        initial_params: Optional[Dict[str, Any]] = None,
        initial_headers: Optional[Dict[str, str]] = None,
        page_param: str = "page",
        per_page_param: str = "per_page",
        page_size: int = 100,
        extract_results: Optional[
            Callable[[Dict[str, Any]], List[Dict[str, Any]]]
        ] = None,
        page_delay: Optional[float] = None,
        http_method: str = HttpMethodEnum.GET.value,
        json_body: Optional[Dict[str, Any]] = None,
        total_pages_path: Optional[str] = None,
        envelope_fields: Optional[List[str]] = None,
    ):
        super().__init__(client)
        self.endpoint = endpoint
        self.initial_params = dict(initial_params or {})
        self.initial_headers = dict(initial_headers or {})
        self.page_param = page_param
        self.per_page_param = per_page_param
        self.page_size = page_size
        self.page_delay = page_delay
        self.extract_results = extract_results or self._default_extract_results
        self.http_method = http_method
        self.json_body = dict(json_body or {})
        self.total_pages_path = total_pages_path
        self.envelope_fields = list(envelope_fields or [])

        if not isinstance(page_size, int) or page_size <= 0:
            raise ValueError(f"page_size must be a positive integer, got {page_size}")
        if http_method not in HttpMethodEnum.get_available_enum_values():
            raise ValueError(
                f"http_method must be one of {HttpMethodEnum.get_available_enum_values()}, "
                f"got {http_method!r}"
            )

        LOGGER.debug(
            "Initialized PagePerPagePaginator endpoint=%s page_param=%s per_page_param=%s "
            "page_size=%d",
            endpoint,
            page_param,
            per_page_param,
            page_size,
        )

    def _default_extract_results(self, data: Dict[str, Any]) -> List[Dict[str, Any]]:
        if isinstance(data, list):
            return data
        if isinstance(data, dict):
            for field in ("results", "items", "data", "content", "records", "entries"):
                if field in data and isinstance(data[field], list):
                    return data[field]
        return []

    def _is_last_page(
        self, data: Any, results: List[Dict[str, Any]], page_index: int
    ) -> bool:
        if not results:
            return True
        if self.total_pages_path:
            total_pages = _get_by_dot_path(data, self.total_pages_path)
            if total_pages is not None and page_index >= int(total_pages):
                return True
        if isinstance(data, dict):
            meta = data.get("metadata")
            if isinstance(meta, dict):
                total_pages = meta.get("totalPages", meta.get("total_pages"))
                current = meta.get("page", meta.get("current_page"))
                if total_pages is not None and current is not None:
                    try:
                        if int(current) >= int(total_pages):
                            return True
                    except (TypeError, ValueError):
                        pass
        return len(results) < self.page_size

    def fetch_all(self) -> Generator[List[Dict[str, Any]], None, None]:
        params = dict(self.initial_params)
        headers = dict(self.initial_headers)
        page_index = 1
        total_records = 0

        LOGGER.info(
            "Starting page/per_page pagination for endpoint '%s' with page_size=%d",
            self.endpoint,
            self.page_size,
        )

        max_pages = 10000

        while True:
            if page_index > max_pages:
                raise ValueError(
                    f"page/per_page pagination exceeded max_pages={max_pages} "
                    f"for endpoint '{self.endpoint}' (missing or inconsistent metadata?)"
                )

            LOGGER.debug(
                "Fetching page %d from '%s' with %s=%s %s=%s",
                page_index,
                self.endpoint,
                self.page_param,
                page_index,
                self.per_page_param,
                self.page_size,
            )

            if self.http_method == HttpMethodEnum.POST.value:
                json_body = dict(self.json_body)
                json_body[self.page_param] = page_index
                json_body[self.per_page_param] = self.page_size
                response = self.client.post(
                    endpoint=self.endpoint,
                    params=dict(params),
                    json=json_body,
                    headers=dict(headers) if headers else None,
                )
            else:
                params[self.page_param] = page_index
                params[self.per_page_param] = self.page_size
                response = self.client.get(
                    endpoint=self.endpoint,
                    params=dict(params),
                    headers=dict(headers) if headers else None,
                )
            data = response.json()

            if isinstance(data, list):
                results = data
            elif isinstance(data, dict):
                results = self.extract_results(data)
                for field in self.envelope_fields:
                    for row in results:
                        if isinstance(row, dict):
                            row[field] = data.get(field)
            else:
                results = []

            total_records += len(results)
            LOGGER.debug("Page %d: retrieved %d results", page_index, len(results))

            if results:
                yield results

            if self._is_last_page(data, results, page_index):
                LOGGER.info(
                    "Pagination complete for '%s'. Fetched %d total records across %d pages.",
                    self.endpoint,
                    total_records,
                    page_index,
                )
                break

            page_index += 1

            if self.page_delay and self.page_delay > 0:
                time.sleep(self.page_delay)
