import json
import logging
from typing import List, Dict, Any

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

DEFAULT_START_TIME = "T00:00:00.000Z"
DEFAULT_END_TIME = "T00:00:00.000Z"
DEFAULT_PARTITION_COLUMN = "event_time"

# Filter placeholder constants
FILTER_PLACEHOLDER_START_DATE = "load_start_date"
FILTER_PLACEHOLDER_END_DATE = "load_end_date"


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
        super().__init__(base_url=API_BASE_URL)

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
                timestamp = BaseAPIClient.format_iso_timestamp(
                    self.load_start_date, DEFAULT_START_TIME
                )
                self.params[key] = timestamp
                LOGGER.info("Filter '%s': %s", key, self.params[key])
            elif value == FILTER_PLACEHOLDER_END_DATE and self.load_end_date:
                timestamp = BaseAPIClient.format_iso_timestamp(
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
            page_delay=PAGINATION_RATE_LIMIT_DELAY,
            retry_on_context_expiration=True,
            max_context_retries=3,
        )

        all_results = []
        for page_results in paginator.fetch_all():
            all_results.extend(page_results)

        return all_results


def main():
    """
    Main entry point for the Greenhouse Audit Log raw layer ingestion job.

    This job:
    1. Parses job arguments (endpoint, filters, dates, partitions, etc.)
    2. Initializes the Greenhouse Audit Log API client
    3. Fetches all paginated data from the API
    4. Converts JSON data to Spark DataFrame
    5. Adds date-based partitions (year, month, day)
    6. Writes data to the raw layer in S3/Databricks
    7. Registers the table in Unity Catalog

    Expected Job Arguments:
        - table_name (str): Name of the table to create/update
        - endpoint (str): API endpoint (e.g., "events")
        - base_filters (dict/str): API query filters with placeholders
        - load_start_date (str): Start date for data extraction (YYYY-MM-DD)
        - load_end_date (str): End date for data extraction (YYYY-MM-DD)
        - partitions (list): Partition columns (default: ["year", "month", "day"])
        - date_column_to_partition (str): Column to use for partitioning
          (default: "event_time")

    Raises:
        Exception: If any error occurs during the ingestion process.
    """
    try:
        job_args = BaseJobArgumentParser.parse_args()
        LOGGER.info(
            f"Running Greenhouse Audit Log job with the following arguments: "
            f"{job_args}"
        )

        spark_client = SparkClient()
        spark = SparkSession.builder.getOrCreate()

        LOGGER.info("Fetching data for table: %s", job_args.get("table_name"))
        api_client = GreenhouseAuditLogAPI(job_args)
        api_data_list = api_client.get_all_paginated_results()

        if api_data_list:
            LOGGER.info(
                "Successfully fetched %d records from API. Converting to DataFrame...",
                len(api_data_list),
            )
            df = json_to_dataframe(spark, api_data_list)

            date_column_to_partition = job_args.get(
                "date_column_to_partition", DEFAULT_PARTITION_COLUMN
            )
            LOGGER.info(
                f"Adding partitions based on column: {date_column_to_partition}"
            )
            df = insert_partitions(df, date_column_to_partition)

            LOGGER.info("Loading data to raw layer...")
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
            LOGGER.info(
                f"Successfully loaded {len(api_data_list)} records for table "
                f"'{job_args.get('table_name')}' into the raw layer."
            )
        else:
            LOGGER.warning(
                f"No data returned from the Audit Log API for table: "
                f"'{job_args.get('table_name')}'. "
                "No data will be loaded in this execution."
            )

    except Exception as e:
        LOGGER.error(
            f"An unhandled error occurred during the Audit Log job execution: {e}",
            exc_info=True,
        )
        raise


if __name__ == "__main__":
    main()
