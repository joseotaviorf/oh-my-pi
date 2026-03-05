import json
import logging
from datetime import date, datetime, timedelta
from typing import List, Dict, Any, Optional, Generator, Tuple

from pyspark.sql import SparkSession

from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.base.api.common.client import BaseAPIClient
from bietlejuice.base.api.parser.argument_parser import BaseJobArgumentParser
from bietlejuice.base.api.auth.oauth2 import BasicAuthOAuth2ClientCredentials
from bietlejuice.base.api.pagination.cursor import CursorPaginator
from bietlejuice.jobs.common.helpers import json_to_dataframe, insert_partitions
from bietlejuice.jobs.common.raw_layer_loader import RawLayerLoader
from bietlejuice.base.api.api_enum import APIEnum

LOGGER = logging.getLogger(__name__)

API_BASE_URL = "https://auditlog.us.greenhouse.io/"
JWT_TOKEN_URL = "https://harvest.greenhouse.io/auth/jwt_access_token"
DATABRICKS_SCOPE = "PEOPLE"
API_KEY_FIELD = "api_key"
TOKEN_EXPIRATION_SECONDS = 60 * 60 * 24  # JWT token valid for 24 hours
TOKEN_EXPIRES_FIELD = "expires"

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
    "integer,string" (exactly 2 components). However, the API sometimes returns
    next_search_after with 3 components. This function ensures we only send
    the first 2 components.

    Args:
        cursor_value: The cursor value from the API response. Can be:
            - A list: [timestamp, hash1, hash2] or [timestamp, hash]
            - A string: "timestamp,hash1,hash2" or "timestamp,hash"

    Returns:
        A properly formatted cursor string with exactly 2 components,
        or None if the cursor is invalid.
    """
    if cursor_value is None:
        return None

    if isinstance(cursor_value, list):
        if len(cursor_value) >= 2:
            return f"{cursor_value[0]},{cursor_value[1]}"
        elif len(cursor_value) == 1:
            return str(cursor_value[0])
        return None

    if isinstance(cursor_value, str):
        parts = [p.strip() for p in cursor_value.split(",")]
        if len(parts) >= 2:
            return f"{parts[0]},{parts[1]}"
        return cursor_value

    return str(cursor_value)


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
        - Token URL: https://harvest.greenhouse.io/auth/jwt_access_token
        - Token expiration: 24 hours (86400 seconds)
        - Accept header: application/json

        The API key is retrieved from Databricks Secrets (PEOPLE scope)
        and used as both client_id and client_secret.
        """
        auth_handler = BasicAuthOAuth2ClientCredentials(
            databricks_scope=DATABRICKS_SCOPE,
            secret_key=APIEnum.GREENHOUSE,
            token_url=JWT_TOKEN_URL,
            client_id_field=API_KEY_FIELD,
            client_secret_field=API_KEY_FIELD,
            expires_at_field=TOKEN_EXPIRES_FIELD,
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
        LOGGER.info("Processing filters. Base filters (before replacement): %s", self.base_filters)
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
            LOGGER.warning("Parameter 'paging' not found in filters. Adding 'paging=true' to enable pagination.")
            self.params["paging"] = "true"
        
        LOGGER.info("Filters processed. Final params to be sent to API: %s", self.params)

    def _extract_pagination_state(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Extracts pagination state from API response with cursor formatting.

        The Greenhouse Audit Log API returns next_search_after with potentially
        3 components, but only accepts 2 components in the Search-After header.
        This method ensures the cursor is properly formatted.

        Args:
            data: The JSON response from the API.

        Returns:
            Dict containing 'cursor' and optionally 'context' (pit_id).
        """
        state = {}

        paging = data.get("paging", {})
        cursor_value = paging.get("next_search_after")
        formatted_cursor = format_search_after_cursor(cursor_value)

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


def get_time_windows(
    start_iso: str, end_iso: str, window_hours: int
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

    Returns:
        Number of records loaded.
    """
    window_args = {**job_args, "load_start_date": load_start, "load_end_date": load_end}
    api_client = GreenhouseAuditLogAPI(window_args)
    api_data_list = api_client.get_all_paginated_results()

    if not api_data_list:
        return 0

    df = json_to_dataframe(spark, api_data_list, raw_column_name="raw_payload")
    date_column_to_partition = job_args.get(
        "date_column_to_partition", DEFAULT_PARTITION_COLUMN
    )
    df = insert_partitions(df, date_column_to_partition)

    raw_loader = RawLayerLoader(
        spark_client=spark_client,
        environment=job_args["environment"],
        source=job_args["dag_name"],
        datalake_bucket=job_args["datalake_bucket"],
        table_name=job_args["table_name"],
        partition_cols=job_args["partition_cols"],
        extraction_type=job_args["extraction_type"],
    )
    raw_loader.load_to_raw(df)
    return len(api_data_list)


def _format_date_for_display(value: Any) -> str:
    """Format load_start_date/load_end_date for logging."""
    if isinstance(value, datetime):
        return value.strftime(GREENHOUSE_API_DATE_FORMAT)
    return str(value)


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
        job_args = BaseJobArgumentParser.parse_args()
        LOGGER.info(
            "Running Greenhouse Audit Log job with the following arguments: %s",
            job_args,
        )

        spark_client = SparkClient()
        spark = SparkSession.builder.getOrCreate()

        load_start = job_args.get("load_start_date")
        load_end = job_args.get("load_end_date")
        backfill_window_hours = job_args.get("backfill_window_hours") or 0
        if isinstance(backfill_window_hours, str):
            try:
                backfill_window_hours = int(backfill_window_hours)
            except ValueError:
                backfill_window_hours = 0

        if backfill_window_hours > 0:
            windows = list(
                get_time_windows(load_start, load_end, backfill_window_hours)
            )
            total_windows = len(windows)
            LOGGER.info(
                "Splitting interval into %d-hour windows: %s to %s -> %d windows",
                backfill_window_hours,
                _format_date_for_display(load_start),
                _format_date_for_display(load_end),
                total_windows,
            )

            total_records = 0
            for i, (window_start, window_end) in enumerate(windows, start=1):
                LOGGER.info(
                    "Processing window %d/%d: %s to %s",
                    i,
                    total_windows,
                    window_start,
                    window_end,
                )
                records = _run_load_for_window(
                    spark, spark_client, job_args, window_start, window_end
                )
                total_records += records
                LOGGER.info(
                    "Completed window %d/%d (%d records)",
                    i,
                    total_windows,
                    records,
                )

            LOGGER.info(
                "Finished processing all %d windows. Total records loaded: %d",
                total_windows,
                total_records,
            )
        else:
            load_start_str = _format_for_greenhouse_api(
                load_start, DEFAULT_START_TIME
            )
            load_end_str = _format_for_greenhouse_api(load_end, DEFAULT_END_TIME)
            LOGGER.info("Fetching data for table: %s", job_args.get("table_name"))
            records = _run_load_for_window(
                spark, spark_client, job_args, load_start_str, load_end_str
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
