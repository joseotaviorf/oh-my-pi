import json
import re
import time
from datetime import date, timedelta

import requests
from pyspark.sql import SparkSession
from quintoandar_logger import QuintoAndarLogger
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from bietlejuice.base.spark.base_spark import BaseDBUtils

LOGGER = QuintoAndarLogger(__name__)


class DegreedAPI:
    """
    A class to interact with the Degreed API, handling authentication
    (with token caching per scope) and fetching paginated data based on dynamic filters.
    """

    _TOKEN_URLS = {
        "PROD": "https://degreed.com/oauth/token",
        "FORNO": "https://degreed.com/oauth/token",
    }
    _API_BASE_URLS = {
        "PROD": "https://api.degreed.com/api/v2/",
        "FORNO": "https://api.degreed.com/api/v2/",
    }
    _REQUEST_DELAY_SECONDS = 0.5
    _MAX_RETRIES = 5
    _BACKOFF_FACTOR = 2
    _SAFE_RESOURCE_ID_PATTERN = re.compile(r"^[a-zA-Z0-9_-]+$")
    _IDS_SOURCE_DATABASE_KEY = "ids_source_database"
    _IDS_SOURCE_TABLE_KEY = "ids_source_table"
    _ID_COLUMN_KEY = "id_column"

    def __init__(self, job_args: dict):
        """
        Initializes the API client using parameters parsed from the job arguments.

        Args:
            job_args (dict): A dictionary containing job parameters like environment,
                             scope, filters, and table_name (endpoint).
        """
        self.environment = job_args.get("environment", "PROD").upper()
        if self.environment not in self._TOKEN_URLS:
            LOGGER.error(
                f"Invalid environment provided: '{self.environment}'. Must be 'PROD' or 'FORNO'."
            )
            raise ValueError(
                f"Invalid environment '{self.environment}'. Use 'PROD' or 'FORNO'."
            )

        self.base_url = self._API_BASE_URLS[self.environment]
        self.endpoint = job_args.get("table_name").replace("_", "-")
        self.scope = job_args.get("scope")
        self.load_start_date = job_args.get("load_start_date")
        self.load_end_date = job_args.get("load_end_date")
        self.base_filters = job_args.get("base_filters", {})
        raw_max_window = job_args.get("max_date_window_days")
        if raw_max_window is not None:
            self.max_date_window_days = int(raw_max_window) if raw_max_window else None
        else:
            self.max_date_window_days = None
        endpoint_path = job_args.get("endpoint_for_id_list") or self.endpoint
        self.endpoint_for_id_list = (endpoint_path or "").replace("_", "-")

        self._client_id, self._client_secret = self._get_secrets()
        self._access_tokens = {}
        self._session = self._create_session_with_retries()

    @staticmethod
    def _date_windows(
        start_date: date, end_date: date, max_days: int
    ) -> list[tuple[date, date]]:
        """
        Splits [start_date, end_date] into non-overlapping windows of at most max_days each.
        """
        if start_date > end_date:
            return []
        if max_days < 1:
            return [(start_date, end_date)]
        windows = []
        current = start_date
        while current <= end_date:
            window_end = min(current + timedelta(days=max_days - 1), end_date)
            windows.append((current, window_end))
            current = window_end + timedelta(days=1)
        return windows

    def _create_session_with_retries(self) -> requests.Session:
        """
        Creates a requests session with automatic retry logic for transient errors.

        Returns:
            requests.Session: A configured session with retry capabilities.
        """
        session = requests.Session()

        retry_strategy = Retry(
            total=self._MAX_RETRIES,
            backoff_factor=self._BACKOFF_FACTOR,
            status_forcelist=[500, 502, 503, 504],
            allowed_methods=["GET", "POST"],
            raise_on_status=False,
        )

        adapter = HTTPAdapter(max_retries=retry_strategy)
        session.mount("http://", adapter)
        session.mount("https://", adapter)

        return session

    def _get_secrets(self):
        """
        Securely retrieves API credentials using Databricks Utilities.

        Returns:
            tuple: A tuple containing the CLIENT_ID and CLIENT_SECRET.
        """
        try:
            base_dbutils = BaseDBUtils()
            dbutils = base_dbutils.get_dbutils()
            raw_secret = dbutils.secrets.get(scope="people", key="DEGREED_API")
            secret = json.loads(raw_secret)
            client_id = secret.get("CLIENT_ID")
            client_secret = secret.get("CLIENT_SECRET")
            if not client_id or not client_secret:
                raise ValueError("CLIENT_ID or CLIENT_SECRET not found in the secret.")
            return client_id, client_secret
        except Exception as e:
            LOGGER.error(f"Failed to retrieve secrets: {e}", exc_info=True)
            raise

    def _fetch_new_token(self, scope: str) -> str:
        """
        Fetches a new access token from the Degreed API for a specific scope.

        Args:
            scope (str): The permission scope for the token.

        Returns:
            str: The access token.
        """
        url = self._TOKEN_URLS[self.environment]
        headers = {"Content-Type": "application/x-www-form-urlencoded"}
        data = {
            "grant_type": "client_credentials",
            "client_id": self._client_id,
            "client_secret": self._client_secret,
            "scope": scope,
        }

        try:
            response = self._session.post(url, headers=headers, data=data)
            if not response.ok:
                try:
                    error_body = response.json()
                except Exception:
                    error_body = response.text or "(empty)"
                LOGGER.error(
                    "OAuth token request failed: url=%s scope=%s status=%s body=%s",
                    url,
                    scope,
                    response.status_code,
                    error_body,
                )
            response.raise_for_status()
            response_json = response.json()
            access_token = response_json.get("access_token")
            if not access_token:
                LOGGER.error(
                    f"Failed to obtain access token, 'access_token' key not in response. Response: {response_json}"
                )
                raise Exception(f"Failed to obtain access token for scope '{scope}'.")

            return access_token
        except requests.exceptions.RequestException as e:
            log_msg = f"HTTP error while fetching token for scope '{scope}': {e}"
            if getattr(e, "response", None) is not None:
                resp = e.response
                try:
                    err_body = resp.json()
                except Exception:
                    err_body = resp.text if resp.text else "(empty)"
                LOGGER.error(
                    "%s response_status=%s response_body=%s",
                    log_msg,
                    resp.status_code,
                    err_body,
                )
            else:
                LOGGER.error(log_msg, exc_info=True)
            raise

    def _fetch_paginated_data_for_params(
        self,
        params: dict,
        auth_headers: dict,
        start_date_override: date | None = None,
        end_date_override: date | None = None,
    ) -> list:
        """
        Fetches all paginated data for a given set of URL parameters.
        Dynamically replaces date placeholders with formatted values.

        Args:
            params (dict): The URL query parameters to be used for the request.
                           May contain the values "load_start_date" and "load_end_date".
            auth_headers (dict): The authentication headers containing the token.
            start_date_override: Optional date to use instead of load_start_date.
            end_date_override: Optional date to use instead of load_end_date.

        Returns:
            list: A list containing all results from all pages.
        """
        processed_params = params.copy()
        start_date = (
            start_date_override
            if start_date_override is not None
            else self.load_start_date
        )
        end_date = (
            end_date_override if end_date_override is not None else self.load_end_date
        )

        for key, value in processed_params.items():
            if value == "load_start_date":
                processed_params[key] = (
                    start_date.strftime("%Y-%m-%d")
                    if start_date and hasattr(start_date, "strftime")
                    else (start_date if start_date else None)
                )

            elif value == "load_end_date":
                processed_params[key] = (
                    end_date.strftime("%Y-%m-%d")
                    if end_date and hasattr(end_date, "strftime")
                    else (end_date if end_date else None)
                )

        results_for_params = []
        next_page_url = f"{self.base_url}{self.endpoint}"
        is_first_request = True
        page_count = 1

        while next_page_url:
            current_params = processed_params if is_first_request else None

            try:
                LOGGER.info(
                    f"Fetching page {page_count} from {next_page_url} with params: {current_params}"
                )

                response = self._session.get(
                    next_page_url,
                    headers=auth_headers,
                    params=current_params,
                    timeout=60,
                )

                LOGGER.info(
                    f"Response status: {response.status_code}, "
                    f"headers: {dict(response.headers)}, "
                    f"elapsed: {response.elapsed.total_seconds()}s"
                )

                if response.status_code >= 400:
                    error_msg = (
                        f"API returned status {response.status_code} on page {page_count}. "
                        f"URL: {next_page_url}, Response: {response.text[:500]}"
                    )
                    LOGGER.error(error_msg)
                    response.raise_for_status()

                is_first_request = False
                json_response = response.json()
                page_data = json_response.get("data", [])

                if page_data:
                    results_for_params.extend(page_data)
                    LOGGER.info(f"Page {page_count} returned {len(page_data)} records")
                else:
                    LOGGER.warning(f"Page {page_count} returned no data")

                next_page_url = json_response.get("links", {}).get("next")
                if next_page_url:
                    page_count += 1
                    time.sleep(self._REQUEST_DELAY_SECONDS)

            except requests.exceptions.HTTPError as e:
                error_details = {
                    "status_code": response.status_code if response else "N/A",
                    "response_body": response.text[:1000] if response else "N/A",
                    "url": next_page_url,
                    "page": page_count,
                    "params": current_params,
                }
                LOGGER.error(
                    f"HTTP error during pagination: {e}. Details: {error_details}",
                    exc_info=True,
                )

                if response and response.status_code >= 500:
                    LOGGER.error(
                        f"Server error {response.status_code} persisted after {self._MAX_RETRIES} retries. "
                        f"This may indicate an issue with the Degreed API. "
                        f"Consider: 1) Checking Degreed API status, "
                        f"2) Reducing the limit parameter, "
                        f"3) Contacting Degreed support if the issue persists."
                    )
                raise
            except requests.exceptions.Timeout as e:
                LOGGER.error(
                    f"Request timeout on page {page_count} after 60 seconds: {e}",
                    exc_info=True,
                )
                raise
            except requests.exceptions.RequestException as e:
                LOGGER.error(
                    f"Request error during pagination on page {page_count}: {e}",
                    exc_info=True,
                )
                raise
            except json.JSONDecodeError as e:
                response_text = response.text if response else "No response"
                LOGGER.error(
                    f"Failed to decode JSON from response on page {page_count}: {e}. "
                    f"Response text: {response_text[:1000]}",
                    exc_info=True,
                )
                raise

        return results_for_params

    def _get_auth_headers(self) -> dict:
        """
        Ensures token for the configured scope is cached and returns auth headers.

        Assumes self.scope is set and valid. Callers must validate scope (and
        endpoint if needed) before calling.
        """
        if self.scope not in self._access_tokens:
            self._access_tokens[self.scope] = self._fetch_new_token(self.scope)
        return {
            "Authorization": f"Bearer {self._access_tokens[self.scope]}",
            "Accept": "application/json",
        }

    def get_all_paginated_results(self) -> list:
        """
        Fetches all results from the configured endpoint.
        When max_date_window_days is set, splits the load date range into
        non-overlapping windows and fetches each window in sequence.

        Returns:
            list: A list containing all results from all pages and all filter combinations.
        """
        if not self.scope:
            LOGGER.error("API scope is not defined in job arguments.")
            raise ValueError(
                "API scope is not defined. Please provide it in the job arguments."
            )
        if not self.endpoint:
            LOGGER.error("API endpoint (table_name) is not defined in job arguments.")
            raise ValueError(
                "API endpoint (table_name) is not defined. Please provide it in the job arguments."
            )

        all_results = []
        auth_headers = self._get_auth_headers()
        params = self.base_filters.copy()

        if not self.max_date_window_days:
            all_results.extend(
                self._fetch_paginated_data_for_params(params, auth_headers)
            )
            return all_results

        if self.load_start_date is None or self.load_end_date is None:
            raise ValueError(
                "load_start_date and load_end_date are required when max_date_window_days is set."
            )
        start_d = (
            self.load_start_date
            if isinstance(self.load_start_date, date)
            else date.fromisoformat(str(self.load_start_date))
        )
        end_d = (
            self.load_end_date
            if isinstance(self.load_end_date, date)
            else date.fromisoformat(str(self.load_end_date))
        )
        windows = self._date_windows(start_d, end_d, self.max_date_window_days)
        total_windows = len(windows)
        LOGGER.info(
            "Fetching %s date window(s) for range %s to %s",
            total_windows,
            start_d,
            end_d,
        )
        for i, (w_start, w_end) in enumerate(windows, 1):
            LOGGER.info(
                "Fetching window %s/%s: %s to %s", i, total_windows, w_start, w_end
            )
            all_results.extend(
                self._fetch_paginated_data_for_params(
                    params.copy(),
                    auth_headers,
                    start_date_override=w_start,
                    end_date_override=w_end,
                )
            )
        return all_results

    def get_by_id(self, resource_id: str, index: int, total: int) -> dict | None:
        """
        Fetches a single resource by ID from the API.

        Uses endpoint_for_id_list from job_args when present (e.g. "pathways" for
        GET /pathways/{id}); otherwise uses the endpoint derived from table_name.

        Args:
            resource_id: The ID of the resource.
            index: The index of the resource in the list.
            total: The total number of resources in the list.
        Returns:
            The response payload (e.g. data key) or None if 404.
        """
        if not self.scope:
            LOGGER.error("API scope is not defined in job arguments.")
            raise ValueError(
                "API scope is not defined. Please provide it in the job arguments."
            )
        if not isinstance(resource_id, str) or not resource_id.strip():
            raise ValueError("resource_id must be a non-empty string.")
        if not self._SAFE_RESOURCE_ID_PATTERN.match(resource_id):
            raise ValueError(
                "resource_id contains invalid characters; only alphanumeric, "
                "hyphen and underscore are allowed to prevent SSRF."
            )
        auth_headers = self._get_auth_headers()
        url = f"{self.base_url}{self.endpoint_for_id_list}/{resource_id}"
        try:
            LOGGER.info(
                f"Fetching resource by id: {url} ({(index)}/{(total)}: {(index / total) * 100:.2f}%)"
            )
            response = self._session.get(url, headers=auth_headers, timeout=60)
            if response.status_code == 404:
                LOGGER.warning(f"Resource not found for id={resource_id}, status=404")
                return None
            response.raise_for_status()
            data = response.json()
            return data.get("data", data)
        except requests.exceptions.RequestException as e:
            LOGGER.error(
                f"Request error fetching resource id={resource_id}: {e}", exc_info=True
            )
            raise
        except json.JSONDecodeError as e:
            LOGGER.error(
                f"Failed to decode JSON for resource id={resource_id}: {e}",
                exc_info=True,
            )
            raise

    def get_by_ids(self, resource_ids: list[str]) -> list:
        """
        Fetches one resource per ID; returns a list of payloads.
        Uses a short delay between requests to reduce rate-limit risk.

        Args:
            resource_ids: List of resource IDs to fetch.

        Returns:
            List of payloads (skips None).
        """
        results = []
        total_resources = len(resource_ids)
        for i, rid in enumerate(resource_ids):
            if i > 0:
                time.sleep(self._REQUEST_DELAY_SECONDS)
            payload = self.get_by_id(rid, i + 1, total_resources)
            if payload is not None:
                results.append(payload)
        return results

    def get_all_from_id_list(self, spark: SparkSession, job_args: dict) -> list:
        """
        Fetches resources by ID list: reads IDs from a Spark table (from job_args),
        validates and filters them for safe URL use, then calls get_by_ids.

        Requires job_args to include ids_source_database, ids_source_table, and
        optionally id_column (default "id").

        Returns:
            List of payloads from the API (one per valid ID).
        """
        self._validate_ids_source(job_args)
        database = job_args[self._IDS_SOURCE_DATABASE_KEY]
        table = job_args[self._IDS_SOURCE_TABLE_KEY]
        id_column = job_args.get(self._ID_COLUMN_KEY, "id")
        ids = self._get_ids_from_table(spark, database, table, id_column)
        if not ids:
            LOGGER.warning(
                "No IDs returned from ids source table. No data will be loaded."
            )
            return []
        LOGGER.info(f"Fetched {len(ids)} IDs from {database}.{table}")
        ids_safe = self._filter_safe_resource_ids(ids)
        if len(ids_safe) < len(ids):
            LOGGER.warning(
                "Dropped %s invalid ID(s) (allowed: alphanumeric, hyphen, underscore)",
                len(ids) - len(ids_safe),
            )
        if not ids_safe:
            LOGGER.warning("No valid IDs to fetch. No data will be loaded.")
            return []
        return self.get_by_ids(ids_safe)

    def _validate_ids_source(self, job_args: dict) -> None:
        if not job_args.get(self._IDS_SOURCE_DATABASE_KEY) or not job_args.get(
            self._IDS_SOURCE_TABLE_KEY
        ):
            raise ValueError(
                "From-id-list ingestion requires extra_details to include "
                f"'{self._IDS_SOURCE_DATABASE_KEY}' and '{self._IDS_SOURCE_TABLE_KEY}'."
            )

    def _get_ids_from_table(
        self, spark: SparkSession, database: str, table: str, id_column: str
    ) -> list[str]:
        full_table_name = f"{database}.{table}"
        LOGGER.info(f"Reading IDs from {full_table_name}, column {id_column}")
        df = spark.table(full_table_name).select(id_column).distinct()
        rows = df.collect()
        return [
            str(getattr(row, id_column))
            for row in rows
            if getattr(row, id_column) is not None
        ]

    def _filter_safe_resource_ids(self, ids: list[str]) -> list[str]:
        """Keep only IDs that are safe for URL path (SSRF mitigation)."""
        return [
            i
            for i in ids
            if isinstance(i, str)
            and i.strip()
            and self._SAFE_RESOURCE_ID_PATTERN.match(i)
        ]
