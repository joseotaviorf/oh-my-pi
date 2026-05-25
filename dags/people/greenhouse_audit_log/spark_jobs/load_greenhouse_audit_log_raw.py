import json
import logging
import time
from datetime import date, datetime, timedelta
from typing import Any, Callable, Dict, Generator, List, Optional, Tuple

from pyspark.sql import SparkSession

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.api.auth.oauth2 import BasicAuthOAuth2ClientCredentials
from bietlejuice.base.api.common.client import BaseAPIClient
from bietlejuice.base.api.pagination.cursor import CursorPaginator
from bietlejuice.base.api.parser.argument_parser import BaseJobArgumentParser
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.jobs.common.helpers import insert_partitions, json_to_dataframe
from bietlejuice.jobs.common.raw_layer_loader import RawLayerLoader

LOGGER = logging.getLogger(__name__)

PIT_ID_EXPIRATION_PATTERNS = ("Pit_Id", "pit_id", "expired")
MAX_PIT_RESUME_ATTEMPTS = 3


class InvalidCursorResumeError(Exception):
    """
    Raised when the API returns a malformed next_search_after cursor that cannot
    be sent back (e.g. single integer when API expects integer,string). Triggers
    resume with after_time, same as Pit_Id expiration.
    """


WRITE_BATCH_SIZE = 5000

API_BASE_URL = "https://auditlog.us.greenhouse.io/"
OAUTH_TOKEN_URL = "https://auth.greenhouse.io/token"
DATABRICKS_SCOPE = "PEOPLE"
TOKEN_EXPIRATION_SECONDS = 60 * 60 * 24  # OAuth token valid for 24 hours

PAGE_SIZE = 500
PAGINATION_RATE_LIMIT_DELAY = 10.5  # Seconds between pages (3 requests per 30s limit)

GREENHOUSE_API_DATE_FORMAT = "%Y-%m-%dT%H:%M:%SZ"
DEFAULT_START_TIME = "T00:00:00Z"
DEFAULT_END_TIME = "T00:00:00Z"
DEFAULT_PARTITION_COLUMN = "event_time"

# Filter placeholder constants
FILTER_PLACEHOLDER_START_DATE = "load_start_date"
FILTER_PLACEHOLDER_END_DATE = "load_end_date"


def _format_for_greenhouse_api(value: Any, time_suffix: str) -> str:
    """
    Formats a date value to Greenhouse API format: YYYY-MM-DDTHH:MM:SSZ.

    The API rejects formats like +00:00Z or milliseconds. This helper
    normalizes any date/datetime/str to the exact format required.

    Args:
        value: Date string (YYYY-MM-DD or ISO), datetime, or date.
        time_suffix: Suffix for date-only strings (e.g. T00:00:00Z, T23:59:59Z).

    Returns:
        String in YYYY-MM-DDTHH:MM:SSZ format.
    """
    if isinstance(value, datetime):
        return value.strftime(GREENHOUSE_API_DATE_FORMAT)
    if isinstance(value, str):
        if "T" in value or " " in value:
            dt = datetime.fromisoformat(value.replace("Z", "+00:00").replace(" ", "T"))
            return dt.strftime(GREENHOUSE_API_DATE_FORMAT)
        return f"{value}{time_suffix}"
    if isinstance(value, date):
        return f"{value.strftime('%Y-%m-%d')}{time_suffix}"
    raise ValueError(f"Cannot format {type(value)} for Greenhouse API: {value}")


def format_search_after_cursor(cursor_value: Any) -> Optional[str]:
    """
    Formats the search_after cursor value for the Greenhouse Audit Log API.

    The Greenhouse API expects the Search-After header to follow the pattern
    "integer,string" (exactly 2 components, with a non-empty string). The API
    sometimes returns next_search_after with 1, 2, or 3 components. This
    function ensures we only send a valid "integer,string" format. When the
    cursor cannot be formatted validly (e.g., single integer only, or empty
    string part), returns None so pagination stops instead of sending an
    invalid request that would cause a 400 error.

    Args:
        cursor_value: The cursor value from the API response. Can be:
            - A list: [timestamp, hash1, hash2] or [timestamp, hash]
            - A string: "timestamp,hash1,hash2" or "timestamp,hash"

    Returns:
        A properly formatted cursor string with exactly 2 components
        (integer, non-empty string), or None if the cursor is invalid.
    """
    if cursor_value is None:
        return None

    if isinstance(cursor_value, list):
        if len(cursor_value) >= 2:
            first = cursor_value[0]
            second = cursor_value[1]
            if first is not None and second is not None and str(second).strip():
                return f"{first},{second}"
        return None

    if isinstance(cursor_value, str):
        parts = [p.strip() for p in cursor_value.split(",")]
        if len(parts) >= 2 and parts[0] and parts[1]:
            return f"{parts[0]},{parts[1]}"
        return None

    return None


class GreenhouseAuditLogAPI(BaseAPIClient):
    """
    API client for Greenhouse Audit Log.

    This client handles authentication, request filtering, and paginated data retrieval
    from the Greenhouse Audit Log API using OAuth2 Client Credentials flow.

    The API uses Point-In-Time (PIT) pagination strategy with:
    - pit_id: Maintains search context across pages
    - search_after: Cursor for the next page
    - Size: Page size in header (100-500)

    Rate Limit: 3 requests per 30 seconds per API key.
    """

    def __init__(self, job_args: Dict[str, Any]):
        """
        Initializes the Greenhouse Audit Log API client.

        Args:
            job_args (Dict[str, Any]): Job arguments containing:
                - endpoint (str): API endpoint to query (e.g., "events")
                - base_filters (dict or str): Filters with placeholders
                - load_start_date (str): Start date for filtering (YYYY-MM-DD)
                - load_end_date (str): End date for filtering (YYYY-MM-DD)
        """
        super().__init__(base_url=API_BASE_URL, min_remaining_threshold=1)

        self.endpoint = job_args.get("endpoint")
        base_filters = job_args.get("base_filters", {})
        if isinstance(base_filters, str):
            try:
                self.base_filters = json.loads(base_filters)
            except json.JSONDecodeError as e:
                LOGGER.error("Failed to parse base_filters JSON: %s", e)
                raise
        else:
            self.base_filters = base_filters

        self.load_start_date = job_args.get("load_start_date")
        self.load_end_date = job_args.get("load_end_date")

        LOGGER.info(
            f"Initializing Greenhouse Audit Log API client for endpoint: {self.endpoint}"
        )
        self._apply_authentication()
        self._process_filters()

    def _apply_authentication(self):
        """
        Configures OAuth2 Client Credentials authentication for the API client.

        Sets up:
        - JWT token-based authentication via Basic Auth OAuth2 flow
        - Token URL: https://auth.greenhouse.io/token (Harvest V3 OAuth)
        - Scope: harvest (required by Greenhouse)
        - Token expiration: from expires_at in response
        - Accept header: application/json

        Credentials (client_id, client_secret) are retrieved from Databricks
        Secrets (PEOPLE scope, GREENHOUSE_AUDIT_LOG_API key).
        """
        auth_handler = BasicAuthOAuth2ClientCredentials(
            databricks_scope=DATABRICKS_SCOPE,
            secret_key=APIEnum.GREENHOUSE_AUDIT_LOG,
            token_url=OAUTH_TOKEN_URL,
            client_id_field="client_id",
            client_secret_field="client_secret",
            token_payload_extras={"scope": "harvest"},
            expires_at_field="expires_at",
            fallback_token_expiration_seconds=TOKEN_EXPIRATION_SECONDS,
        )
        auth_handler.apply_auth(self.session)
        self.session.headers.update({"Accept": "application/json"})

    def _process_filters(self):
        """
        Processes base filters and replaces placeholders with actual date values.

        Placeholder values are replaced as follows:
        - "load_start_date" → ISO-8601 timestamp with start-of-day time (T00:00:00.000Z)
        - "load_end_date" → ISO-8601 timestamp with end-of-day time (T23:59:59.999Z)
        - Other values → Used as-is

        The resulting filters are stored in self.params and will be sent as
        query parameters in API requests.
        """
        LOGGER.info(
            "Processing filters. Base filters (before replacement): %s",
            self.base_filters,
        )
        self.params = {}

        for key, value in self.base_filters.items():
            if value == FILTER_PLACEHOLDER_START_DATE and self.load_start_date:
                timestamp = _format_for_greenhouse_api(
                    self.load_start_date, DEFAULT_START_TIME
                )
                self.params[key] = timestamp
                LOGGER.info("Filter '%s': %s", key, self.params[key])
            elif value == FILTER_PLACEHOLDER_END_DATE and self.load_end_date:
                timestamp = _format_for_greenhouse_api(
                    self.load_end_date, DEFAULT_END_TIME
                )
                self.params[key] = timestamp
                LOGGER.info("Filter '%s': %s", key, self.params[key])
            else:
                self.params[key] = value

        if "paging" not in self.params:
            LOGGER.warning(
                "Parameter 'paging' not found in filters. Adding 'paging=true' to enable pagination."
            )
            self.params["paging"] = "true"

        LOGGER.info(
            "Filters processed. Final params to be sent to API: %s", self.params
        )

    def _extract_pagination_state(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Extracts pagination state from API response with cursor formatting.

        The Greenhouse Audit Log API returns next_search_after with potentially
        3 components, but only accepts 2 components in the Search-After header.
        This method ensures the cursor is properly formatted.

        When the API returns a malformed cursor (e.g. single integer) but we
        have results, raises InvalidCursorResumeError to trigger resume with
        after_time (same as Pit_Id expiration).

        Args:
            data: The JSON response from the API.

        Returns:
            Dict containing 'cursor' and optionally 'context' (pit_id).

        Raises:
            InvalidCursorResumeError: When cursor is malformed and we have
                results, signaling that resume with after_time should be tried.
        """
        state = {}

        paging = data.get("paging", {})
        cursor_value = paging.get("next_search_after")
        formatted_cursor = format_search_after_cursor(cursor_value)

        if cursor_value is not None and formatted_cursor is None:
            results = data.get("results", [])
            if results:
                raise InvalidCursorResumeError(
                    f"Invalid cursor format (cannot produce integer,string): {cursor_value}. "
                    "Will resume with after_time."
                )

        if formatted_cursor is not None:
            state["cursor"] = formatted_cursor
            LOGGER.debug(
                "Formatted cursor from '%s' to '%s'",
                cursor_value,
                formatted_cursor,
            )

        context_value = paging.get("pit_id")
        if context_value is not None:
            state["context"] = context_value

        return state

    def _is_pit_id_expired(self, error: Exception) -> bool:
        """
        Checks if the error indicates Pit_Id expiration.

        Per Greenhouse docs, when Pit_Id expires the API returns:
        "The Pit_Id has expired. Remove it from the subsequent search."
        """
        error_str = str(error)
        return any(pattern in error_str for pattern in PIT_ID_EXPIRATION_PATTERNS)

    def _get_max_event_time(self, results: List[Dict[str, Any]]) -> Optional[str]:
        """
        Extracts the maximum event_time from results for resume.

        Returns ISO-8601 formatted string for after_time parameter.
        """
        event_times = [
            r.get("event_time") for r in results if r.get("event_time") is not None
        ]
        if not event_times:
            return None
        return max(event_times)

    def _should_resume_on_error(self, error: Exception) -> bool:
        """
        Checks if the error indicates we should resume with after_time.

        Applies to Pit_Id expiration and InvalidCursorResumeError (malformed
        next_search_after that cannot be sent back to the API).
        """
        if isinstance(error, InvalidCursorResumeError):
            return True
        return self._is_pit_id_expired(error)

    def fetch_pages_with_resume(
        self,
        on_page: Callable[[List[Dict[str, Any]]], None],
        on_before_resume: Optional[Callable[[], None]] = None,
    ) -> Tuple[int, int]:
        """
        Fetches all pages with Pit_Id and invalid-cursor resume per Greenhouse docs.

        When Pit_Id expires or the API returns a malformed next_search_after
        cursor, starts a new request with after_time set to the last event's
        event_time. Writes to S3 incrementally via on_page callback so progress
        is persisted. After max resume attempts, returns what was fetched
        instead of failing.

        Args:
            on_page: Callback invoked for each page of results (for streaming write).
            on_before_resume: Optional callback invoked before resuming with new
                after_time. Use to flush any unwritten buffered data.

        Returns:
            Tuple of (total_records_fetched, resume_count).
        """
        if not self.endpoint:
            raise ValueError(
                "API endpoint (table_name) is not defined in the job arguments."
            )

        params = self.params.copy()
        LOGGER.info(
            "Starting fetch for endpoint '%s' with window after_time=%s, before_time=%s",
            self.endpoint,
            params.get("after_time"),
            params.get("before_time"),
        )
        total_records = 0
        resume_attempt = 0

        while resume_attempt < MAX_PIT_RESUME_ATTEMPTS:
            paginator = CursorPaginator(
                client=self,
                endpoint=self.endpoint,
                initial_params=params,
                cursor_param="Search-After",
                cursor_location="header",
                cursor_response_path="paging.next_search_after",
                context_param="Pit-Id",
                context_location="header",
                context_response_path="paging.pit_id",
                page_size_param="Size",
                page_size_location="header",
                page_size=PAGE_SIZE,
                extract_results=lambda data: data.get("results", []),
                extract_pagination_state=self._extract_pagination_state,
                page_delay=PAGINATION_RATE_LIMIT_DELAY,
                retry_on_context_expiration=False,
            )

            batch_for_resume: List[Dict[str, Any]] = []

            try:
                for page_results in paginator.fetch_all():
                    batch_for_resume.extend(page_results)
                    total_records += len(page_results)
                    on_page(page_results)

                LOGGER.info(
                    "Pagination complete for '%s'. Fetched %d total records.",
                    self.endpoint,
                    total_records,
                )
                return total_records, resume_attempt

            except Exception as e:
                if not self._should_resume_on_error(e):
                    raise

                if not batch_for_resume:
                    LOGGER.error(
                        "Resume triggered before any records were fetched. Cannot resume."
                    )
                    raise

                if on_before_resume:
                    on_before_resume()

                last_event_time = self._get_max_event_time(batch_for_resume)
                if not last_event_time:
                    LOGGER.error(
                        "Resume triggered but no event_time found in results. Cannot resume."
                    )
                    raise

                resume_attempt += 1
                params["after_time"] = last_event_time

                error_type = (
                    "Invalid cursor"
                    if isinstance(e, InvalidCursorResumeError)
                    else "Pit_Id expired"
                )
                LOGGER.warning(
                    "%s. Resuming with after_time=%s (attempt %d/%d). "
                    "Records fetched so far: %d. Window: after_time=%s, before_time=%s",
                    error_type,
                    last_event_time,
                    resume_attempt,
                    MAX_PIT_RESUME_ATTEMPTS,
                    total_records,
                    self.params.get("after_time", "N/A"),
                    self.params.get("before_time", "N/A"),
                )

        LOGGER.warning(
            "Max resume attempts (%d) reached. Returning %d records fetched so far.",
            MAX_PIT_RESUME_ATTEMPTS,
            total_records,
        )
        return total_records, resume_attempt

    def get_all_paginated_results(self) -> List[Dict[str, Any]]:
        """
        Fetches all paginated results from the Greenhouse Audit Log API.

        Uses CursorPaginator with Point-In-Time pagination strategy.
        The Greenhouse Audit Log API uses:
        - pit_id: Point-In-Time ID (maintains search context across pages)
        - next_search_after: Cursor for the next page
        - Both sent via request headers

        The CursorPaginator automatically handles PIT_ID expiration by restarting
        pagination with a fresh PIT_ID when expiration is detected.

        Returns:
            List[Dict[str, Any]]: List of all audit log events.

        Raises:
            ValueError: If endpoint is not defined.
        """
        if not self.endpoint:
            raise ValueError(
                "API endpoint (table_name) is not defined in the job arguments."
            )

        full_url = f"{API_BASE_URL}{self.endpoint}"
        LOGGER.info(
            "Starting Point-In-Time paginated fetch for endpoint: '%s' with parameters: %s",
            self.endpoint,
            self.params,
        )
        LOGGER.info(
            "Full API URL: %s",
            full_url,
        )

        paginator = CursorPaginator(
            client=self,
            endpoint=self.endpoint,
            initial_params=self.params,
            cursor_param="Search-After",
            cursor_location="header",
            cursor_response_path="paging.next_search_after",
            context_param="Pit-Id",
            context_location="header",
            context_response_path="paging.pit_id",
            page_size_param="Size",
            page_size_location="header",
            page_size=PAGE_SIZE,
            extract_results=lambda data: data.get("results", []),
            extract_pagination_state=self._extract_pagination_state,
            page_delay=PAGINATION_RATE_LIMIT_DELAY,
            retry_on_context_expiration=True,
            max_context_retries=3,
        )

        all_results = []
        for page_results in paginator.fetch_all():
            all_results.extend(page_results)

        return all_results


def _log_window_metrics(
    table_name: str,
    load_start: str,
    load_end: str,
    records_loaded: int,
    pit_id_resume_count: int,
    elapsed_seconds: float,
) -> None:
    """Logs observability metrics for a single window."""
    LOGGER.info(
        "GreenhouseAuditLog window metrics: table=%s, load_start=%s, load_end=%s, "
        "records_loaded=%d, pit_id_resume_count=%d, elapsed_seconds=%.2f",
        table_name,
        load_start,
        load_end,
        records_loaded,
        pit_id_resume_count,
        elapsed_seconds,
        extra={
            "greenhouse_audit_log_records_loaded": records_loaded,
            "greenhouse_audit_log_pit_id_resume_count": pit_id_resume_count,
            "greenhouse_audit_log_elapsed_seconds": round(elapsed_seconds, 2),
        },
    )


def get_time_windows(
    start_iso: str, end_iso: str, window_hours: float
) -> Generator[Tuple[str, str], None, None]:
    """
    Yields (load_start, load_end) ISO strings for each N-hour window.

    Args:
        start_iso: Start of interval (ISO-8601 or YYYY-MM-DD).
        end_iso: End of interval (ISO-8601 or YYYY-MM-DD).
        window_hours: Size of each window in hours.

    Yields:
        Tuples of (window_start_iso, window_end_iso).
    """
    start = _parse_datetime(start_iso)
    end = _parse_datetime(end_iso)
    current = start
    while current < end:
        window_end = min(current + timedelta(hours=window_hours), end)
        yield (
            current.strftime(GREENHOUSE_API_DATE_FORMAT),
            window_end.strftime(GREENHOUSE_API_DATE_FORMAT),
        )
        current = window_end


def _parse_datetime(value: Any) -> datetime:
    """Parse datetime from string or datetime object."""
    if isinstance(value, datetime):
        return value
    if isinstance(value, str):
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    raise ValueError(f"Cannot parse datetime from {type(value)}: {value}")


def _run_load_for_window(
    spark: SparkSession,
    spark_client: SparkClient,
    job_args: Dict[str, Any],
    load_start: str,
    load_end: str,
) -> int:
    """
    Fetches data for a single time window and loads to raw layer.

    Uses fetch_pages_with_resume for Pit_Id expiration handling per Greenhouse
    docs: when Pit_Id expires, resumes with after_time=last event_time.
    Writes to S3 incrementally so progress is persisted before expiration.

    For ``extraction_type`` incremental, defers metastore recreation, grants, and
    ``REFRESH TABLE`` to a single call at the end of the window so each append batch
    avoids repeated Unity Catalog refresh (major runtime cost).

    Returns:
        Number of records loaded.
    """
    window_args = {**job_args, "load_start_date": load_start, "load_end_date": load_end}
    api_client = GreenhouseAuditLogAPI(window_args)

    raw_loader = RawLayerLoader(
        spark_client=spark_client,
        environment=job_args["environment"],
        source=job_args["dag_name"],
        datalake_bucket=job_args["datalake_bucket"],
        table_name=job_args["table_name"],
        partition_cols=job_args["partition_cols"],
        extraction_type=job_args["extraction_type"],
    )
    date_column_to_partition = job_args.get(
        "date_column_to_partition", DEFAULT_PARTITION_COLUMN
    )

    extraction_type = str(job_args.get("extraction_type", "incremental")).lower()
    use_incremental_metastore_strategy = extraction_type == "incremental"

    batch: List[Dict[str, Any]] = []
    page_count = [0]
    cumulative_records = [0]
    any_write_in_window = [False]

    def write_batch_to_s3() -> None:
        if not batch:
            return
        batch_size = len(batch)
        LOGGER.info(
            "Writing batch of %d records to raw layer (window %s to %s)",
            batch_size,
            load_start,
            load_end,
        )
        df = json_to_dataframe(spark, batch, raw_column_name="raw_payload")
        df = insert_partitions(df, date_column_to_partition)
        any_write_in_window[0] = True
        if use_incremental_metastore_strategy:
            raw_loader.load_to_raw(
                df,
                metastore_force_recreate=False,
                apply_table_privileges=False,
                refresh_table_after_load=False,
            )
        else:
            raw_loader.load_to_raw(df)
        batch.clear()
        LOGGER.info("Batch write completed successfully")

    def on_page(page_results: List[Dict[str, Any]]) -> None:
        page_count[0] += 1
        cumulative_records[0] += len(page_results)
        batch.extend(page_results)
        if page_count[0] % 10 == 0:
            LOGGER.info(
                "Fetch progress: page %d, cumulative records %d (window %s to %s)",
                page_count[0],
                cumulative_records[0],
                load_start,
                load_end,
            )
        if len(batch) >= WRITE_BATCH_SIZE:
            write_batch_to_s3()

    window_start_time = time.time()
    total_records, pit_id_resume_count = api_client.fetch_pages_with_resume(
        on_page=on_page,
        on_before_resume=write_batch_to_s3,
    )
    write_batch_to_s3()
    if any_write_in_window[0] and use_incremental_metastore_strategy:
        raw_loader.finalize_raw_layer_visibility()

    elapsed_seconds = time.time() - window_start_time

    _log_window_metrics(
        table_name=job_args["table_name"],
        load_start=load_start,
        load_end=load_end,
        records_loaded=total_records,
        pit_id_resume_count=pit_id_resume_count,
        elapsed_seconds=elapsed_seconds,
    )

    if total_records == 0:
        LOGGER.warning(
            "Window returned 0 records: %s to %s (table=%s). "
            "API may have no data for this period or filters may exclude all events.",
            load_start,
            load_end,
            job_args["table_name"],
        )

    return total_records, pit_id_resume_count


def _format_date_for_display(value: Any) -> str:
    """Format load_start_date/load_end_date for logging."""
    if isinstance(value, datetime):
        return value.strftime(GREENHOUSE_API_DATE_FORMAT)
    return str(value)


def _log_execution_metrics(
    table_name: str,
    total_records: int,
    total_pit_id_resumes: int,
    total_windows: int,
    elapsed_seconds: float,
) -> None:
    """Logs final observability metrics for the full job execution."""
    LOGGER.info(
        "GreenhouseAuditLog execution metrics: table=%s, total_records=%d, "
        "total_pit_id_resumes=%d, total_windows=%d, total_elapsed_seconds=%.2f",
        table_name,
        total_records,
        total_pit_id_resumes,
        total_windows,
        elapsed_seconds,
        extra={
            "greenhouse_audit_log_total_records": total_records,
            "greenhouse_audit_log_total_pit_id_resumes": total_pit_id_resumes,
            "greenhouse_audit_log_total_windows": total_windows,
            "greenhouse_audit_log_total_elapsed_seconds": round(elapsed_seconds, 2),
        },
    )


def main():
    """
    Main entry point for the Greenhouse Audit Log raw layer ingestion job.

    This job:
    1. Parses job arguments (endpoint, filters, dates, partitions, etc.)
    2. Optionally splits the interval into N-hour windows (backfill_window_hours)
    3. For each window: fetches from API, converts to DataFrame, loads to raw layer

    Expected Job Arguments:
        - table_name (str): Name of the table to create/update
        - endpoint (str): API endpoint (e.g., "events")
        - base_filters (dict/str): API query filters with placeholders
        - load_start_date (str): Start date for data extraction
        - load_end_date (str): End date for data extraction
        - backfill_window_hours (int, optional): When set, splits interval into
          N-hour windows and processes each sequentially.
        - partitions (list): Partition columns (default: ["year", "month", "day"])
        - date_column_to_partition (str): Column to use for partitioning
          (default: "event_time")

    Raises:
        Exception: If any error occurs during the ingestion process.
    """
    try:
        job_start_time = time.time()
        job_args = BaseJobArgumentParser.parse_args()
        LOGGER.info(
            "Greenhouse Audit Log job started: dag=%s, table=%s, env=%s, extraction=%s, "
            "load_start=%s, load_end=%s, backfill_window_hours=%s",
            job_args.get("dag_name"),
            job_args.get("table_name"),
            job_args.get("environment"),
            job_args.get("extraction_type"),
            job_args.get("load_start_date"),
            job_args.get("load_end_date"),
            job_args.get("backfill_window_hours"),
        )
        LOGGER.info("Full job arguments: %s", job_args)

        spark_client = SparkClient()
        spark = SparkSession.builder.getOrCreate()

        load_start = job_args.get("load_start_date")
        load_end = job_args.get("load_end_date")
        backfill_window_hours = job_args.get("backfill_window_hours") or 0
        if isinstance(backfill_window_hours, str):
            try:
                backfill_window_hours = float(backfill_window_hours)
            except ValueError:
                backfill_window_hours = 0

        total_records = 0
        total_pit_id_resumes = 0

        if backfill_window_hours > 0:
            windows = list(
                get_time_windows(load_start, load_end, backfill_window_hours)
            )
            total_windows = len(windows)
            LOGGER.info(
                "Splitting interval into %.1f-hour windows: %s to %s -> %d windows",
                backfill_window_hours,
                _format_date_for_display(load_start),
                _format_date_for_display(load_end),
                total_windows,
            )

            for i, (window_start, window_end) in enumerate(windows, start=1):
                LOGGER.info(
                    "Processing window %d/%d: %s to %s",
                    i,
                    total_windows,
                    window_start,
                    window_end,
                )
                records, pit_resumes = _run_load_for_window(
                    spark, spark_client, job_args, window_start, window_end
                )
                total_records += records
                total_pit_id_resumes += pit_resumes
                LOGGER.info(
                    "Completed window %d/%d (%d records, %d Pit_Id resumes)",
                    i,
                    total_windows,
                    records,
                    pit_resumes,
                )

            elapsed_seconds = time.time() - job_start_time
            _log_execution_metrics(
                table_name=job_args.get("table_name"),
                total_records=total_records,
                total_pit_id_resumes=total_pit_id_resumes,
                total_windows=total_windows,
                elapsed_seconds=elapsed_seconds,
            )
            LOGGER.info(
                "Finished processing all %d windows. Total records loaded: %d",
                total_windows,
                total_records,
            )
        else:
            load_start_str = _format_for_greenhouse_api(load_start, DEFAULT_START_TIME)
            load_end_str = _format_for_greenhouse_api(load_end, DEFAULT_END_TIME)
            LOGGER.info("Fetching data for table: %s", job_args.get("table_name"))
            records, pit_resumes = _run_load_for_window(
                spark, spark_client, job_args, load_start_str, load_end_str
            )
            total_records = records
            total_pit_id_resumes = pit_resumes
            elapsed_seconds = time.time() - job_start_time
            _log_execution_metrics(
                table_name=job_args.get("table_name"),
                total_records=total_records,
                total_pit_id_resumes=total_pit_id_resumes,
                total_windows=1,
                elapsed_seconds=elapsed_seconds,
            )
            if records > 0:
                LOGGER.info(
                    "Successfully loaded %d records for table '%s' into the raw layer.",
                    records,
                    job_args.get("table_name"),
                )
            else:
                LOGGER.warning(
                    "No data returned from the Audit Log API for table '%s'. "
                    "No data will be loaded in this execution.",
                    job_args.get("table_name"),
                )

    except Exception as e:
        LOGGER.error(
            "An unhandled error occurred during the Audit Log job execution: %s",
            e,
            exc_info=True,
        )
        raise


if __name__ == "__main__":
    main()
