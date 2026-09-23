"""
Configuration loader for API Ingestion workflow.

This module provides functionality to instantiate API components (authentication,
pagination, rate limiting) at runtime based on YAML configuration.

Example:
    workflow_config = {"api_base_url": "https://api.example.com", "authentication": {"strategy": "none"}}
    table_config = {"endpoint_path": "events"}
    loader = APIConfigurationLoader(workflow_config, table_config)
    client = loader.create_api_client()
    paginator = loader.create_paginator(client, "events", {})

TODO: incomplete — no Spark entry-point exists yet (no `type: api_ingestion` DAG declarations).
The Airflow workflow class (RawAPIIngestionWorkflow) is in place but there is no corresponding
load_api_ingestion_raw.py spark job to submit. This file and its siblings (api_key.py, basic.py,
offset_limit.py) are unreachable from production until that Spark entry-point is created.
"""

import logging
import os
from typing import Any, Dict, Optional

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.api_ingestion_enums import (
    AuthenticationStrategyEnum,
    HttpMethodEnum,
    PaginationStrategyEnum,
    RateLimitingStrategyEnum,
)
from bietlejuice.base.api.auth.api_key import APIKeyAuth
from bietlejuice.base.api.auth.basic import BasicAuth
from bietlejuice.base.api.auth.oauth2 import BasicAuthOAuth2ClientCredentials
from bietlejuice.base.api.common.client import BaseAPIClient
from bietlejuice.base.api.configuration.date_format import (
    END_OF_DAY_SUFFIX,
    START_OF_DAY_SUFFIX,
    format_load_date,
)
from bietlejuice.base.api.pagination.base import BasePaginator
from bietlejuice.base.api.pagination.cursor import CursorPaginator
from bietlejuice.base.api.pagination.offset_limit import OffsetLimitPaginator
from bietlejuice.base.api.pagination.page_per_page import PagePerPagePaginator
from bietlejuice.base.spark.base_spark import BaseDBUtils

LOGGER = logging.getLogger(__name__)

DEFAULT_MAX_RETRIES = 3
DATE_PLACEHOLDERS = ("load_start_date", "load_end_date")


class APIConfigurationLoader:
    """
    Loads and instantiates API components based on YAML configuration.

    Configuration is read from two levels: workflow_config (shared across tables)
    and table_config (table-specific). Table-level config overrides workflow-level
    for overlapping keys (e.g., pagination, api_policies).
    """

    def __init__(self, workflow_config: Dict[str, Any], table_config: Dict[str, Any]):
        """
        Initializes the configuration loader.

        Args:
            workflow_config: Workflow-level configuration from YAML
            table_config: Table-specific configuration from YAML
        """
        self.workflow_config = workflow_config
        self.table_config = table_config

    def get_api_base_url(self) -> str:
        """
        Returns the base URL for the API based on the current environment.

        This method supports two formats for api_base_url:
        - String: Used when the same URL applies to all environments
        - Dict: Used when different URLs are needed per environment (e.g., {'prod': '...', 'forno': '...'})

        Returns:
            str: The base URL for the API

        Raises:
            ValueError: If api_base_url is not configured or environment is invalid
        """
        api_base_url = self.workflow_config.get("api_base_url")
        if api_base_url is None:
            raise ValueError("'api_base_url' is required in workflow configuration")

        if isinstance(api_base_url, str):
            return api_base_url

        if isinstance(api_base_url, dict):
            if len(api_base_url) == 0:
                raise ValueError(
                    "Base URL not found for environment. Available environments: []"
                )
            environment = os.environ.get("ENVIRONMENT", "forno").lower()
            base_url = api_base_url.get(environment)
            if not base_url:
                raise ValueError(
                    f"Base URL not found for environment '{environment}'. "
                    f"Available environments: {list(api_base_url.keys())}"
                )
            return base_url

        raise ValueError(
            f"'api_base_url' must be either a string or a dictionary, "
            f"got {type(api_base_url).__name__}"
        )

    def get_http_user_agent(self) -> Optional[str]:
        """
        Returns the optional HTTP User-Agent string for API and token requests.

        When unset or blank, the client does not override ``requests`` defaults
        for the session (OAuth token calls likewise omit a custom User-Agent).

        Returns:
            Optional[str]: Non-empty ``workflow.http_user_agent`` or None.
        """
        ua = self.workflow_config.get("http_user_agent")
        if ua is None or not isinstance(ua, str):
            return None
        stripped = ua.strip()
        return stripped or None

    def get_http_headers(self) -> Dict[str, str]:
        """
        Returns static HTTP headers merged from workflow then table config.

        Table keys overlay workflow keys. A missing table map inherits the
        workflow map. ``http_user_agent`` remains the User-Agent knob and is
        applied after these headers in ``create_api_client``.

        Returns:
            Dict[str, str]: Merged header name → value. Empty if unset.

        Raises:
            ValueError: If a present ``http_headers`` value is not a mapping.
        """
        merged: Dict[str, str] = {}
        for source in (
            self.workflow_config.get("http_headers"),
            self.table_config.get("http_headers"),
        ):
            if source is None:
                continue
            if not isinstance(source, dict):
                raise ValueError(
                    "'http_headers' must be a mapping of header name to string value"
                )
            merged.update(source)
        return merged

    def create_api_client(self) -> BaseAPIClient:
        """
        Creates and configures a BaseAPIClient with authentication applied.

        Instantiates BaseAPIClient with base_url and max_retries. max_retries is
        resolved from: retry_policy.retries, then error_handling.max_retries,
        else DEFAULT_MAX_RETRIES (3). Authentication is applied based on the strategy in YAML
        (oauth2_client_credentials, basic, api_key, or none). Rate limiting and
        error handling configs are validated; fixed_delay is applied during
        pagination, not at client level. Alert channel and non_fatal_status_codes
        are logged for visibility but not yet passed to BaseAPIClient.

        Returns:
            BaseAPIClient: Configured client with authentication applied

        Raises:
            ValueError: If authentication or rate limiting strategy is not supported
        """
        base_url = self.get_api_base_url()

        workflow_api_policies = self.workflow_config.get("api_policies", {})
        table_api_policies = self.table_config.get("api_policies", {})

        workflow_rate_limiting = workflow_api_policies.get("rate_limiting", {})
        table_rate_limiting = table_api_policies.get("rate_limiting", {})
        rate_limiting = {}
        rate_limiting.update(workflow_rate_limiting)
        rate_limiting.update(table_rate_limiting)

        workflow_error_handling = workflow_api_policies.get("error_handling", {})
        table_error_handling = table_api_policies.get("error_handling", {})
        error_handling = {}
        error_handling.update(workflow_error_handling)
        error_handling.update(table_error_handling)

        retry_policy = error_handling.get("retry_policy")
        non_fatal_status_codes = error_handling.get("non_fatal_status_codes")
        if isinstance(retry_policy, dict) and retry_policy.get("retries") is not None:
            max_retries = retry_policy["retries"]
        elif error_handling.get("max_retries") is not None:
            max_retries = error_handling["max_retries"]
        else:
            max_retries = DEFAULT_MAX_RETRIES

        alert_channel = self.workflow_config.get("alert_channel")
        if alert_channel:
            try:
                BaseDBUtils().get_dbutils()
            except Exception as e:
                LOGGER.warning(
                    f"Could not obtain dbutils for alert channel service: {e}. "
                    "Alerts may not be sent if dbutils is required."
                )

        client = BaseAPIClient(base_url=base_url, max_retries=max_retries)

        authentication = self.table_config.get(
            "authentication"
        ) or self.workflow_config.get("authentication")
        if authentication is not None:
            if authentication == {}:
                raise ValueError(
                    "Authentication strategy is required and cannot be empty. "
                    "Supported strategies: oauth2_client_credentials, basic, none"
                )
            strategy = authentication.get("strategy")
            if not strategy or strategy == "":
                raise ValueError(
                    "Authentication strategy is required and cannot be empty. "
                    "Supported strategies: oauth2_client_credentials, basic, none"
                )
            if strategy == AuthenticationStrategyEnum.OAUTH2_CLIENT_CREDENTIALS.value:
                self._apply_oauth2_authentication(client, authentication)
            elif strategy == AuthenticationStrategyEnum.BASIC.value:
                self._apply_basic_authentication(client, authentication)
            elif strategy == AuthenticationStrategyEnum.API_KEY.value:
                self._apply_api_key_authentication(client, authentication)
            elif strategy == AuthenticationStrategyEnum.NONE.value:
                LOGGER.info("No authentication strategy configured")
            else:
                raise ValueError(
                    f"Authentication strategy '{strategy}' not supported. "
                    "Supported strategies: oauth2_client_credentials, basic, api_key, none"
                )

        rate_limiting_strategy = rate_limiting.get("strategy")
        if rate_limiting_strategy == RateLimitingStrategyEnum.FIXED_DELAY.value:
            LOGGER.info("Fixed delay rate limiting will be applied during pagination")
        elif rate_limiting_strategy == RateLimitingStrategyEnum.NONE.value:
            LOGGER.info("No rate limiting strategy configured")
        elif rate_limiting_strategy == "":
            raise ValueError(
                "Rate limiting strategy cannot be empty string. "
                "Supported strategies: fixed_delay, none"
            )
        elif rate_limiting_strategy:
            raise ValueError(
                f"Rate limiting strategy '{rate_limiting_strategy}' not supported in MVP phase"
            )

        if retry_policy:
            retries = retry_policy.get("retries")
            delay = retry_policy.get("delay")
            backoff_factor = retry_policy.get("backoff_factor")
            if retries and delay is not None and backoff_factor is not None:
                LOGGER.info(
                    f"Retry policy configured: {retries} retries, delay={delay}s, backoff_factor={backoff_factor}"
                )
            else:
                LOGGER.info(f"Retry policy configured: {retry_policy}")
        if non_fatal_status_codes:
            LOGGER.info(
                f"Non-fatal status codes configured: {non_fatal_status_codes}. "
                f"Errors with these codes will be logged but will not cause job failure."
            )
        else:
            LOGGER.info(
                "No non-fatal status codes configured. All HTTP errors will cause job failure (fail-fast)."
            )

        if alert_channel:
            LOGGER.info(
                f"Alert channel configured: '{alert_channel}'. "
                "All HTTP errors will trigger alerts to this channel."
            )
        else:
            LOGGER.info(
                "No alert channel configured. Alerts will not be sent for HTTP errors."
            )

        http_headers = self.get_http_headers()
        if http_headers:
            client.session.headers.update(http_headers)

        http_user_agent = self.get_http_user_agent()
        if http_user_agent:
            client.session.headers["User-Agent"] = http_user_agent

        return client

    def _apply_oauth2_authentication(
        self, client: BaseAPIClient, auth_config: Dict[str, Any]
    ):
        """
        Applies OAuth2 Client Credentials authentication to the client.

        This method configures OAuth2 Client Credentials flow authentication for the API client.
        It retrieves the secret key and token URL from the authentication configuration and uses
        BasicAuthOAuth2ClientCredentials handler to manage token acquisition and refresh. The handler
        supports customizable secret field names to accommodate different API secret formats.

        The secret fields are configurable via YAML:
        - client_secret_field: Field name in the secret for client secret (default: "client_secret")
        - client_id_field: Field name in the secret for client ID (default: "client_id", or same as client_secret_field if only client_secret_field is specified)
        - expires_at_field: Field name in token response for expiration (default: "expires")
        - fallback_token_expiration_seconds: Fallback expiration if not provided (default: 86400)

        Args:
            client: The API client to configure with authentication
            auth_config: Authentication configuration from YAML containing secret_key,
                        token_url, and optional scopes, client_id_field, client_secret_field,
                        expires_at_field, and fallback_token_expiration_seconds

        Raises:
            ValueError: If secret_key or token_url are not provided in the configuration
        """
        secret_key = auth_config.get("secret_key")
        token_url = auth_config.get("token_url")

        if not secret_key:
            raise ValueError(
                "'secret_key' is required for oauth2_client_credentials authentication"
            )
        if not token_url:
            raise ValueError(
                "'token_url' is required for oauth2_client_credentials authentication"
            )

        client_secret_field = auth_config.get("client_secret_field", "client_secret")
        client_id_field = auth_config.get("client_id_field")
        if client_id_field is None or client_id_field == "":
            if "client_secret_field" in auth_config:
                client_id_field = client_secret_field
            else:
                client_id_field = "client_id"
        expires_at_field = auth_config.get("expires_at_field", "expires_at")
        fallback_token_expiration_seconds = auth_config.get(
            "fallback_token_expiration_seconds", 60 * 60 * 24
        )

        databricks_scope = self.workflow_config.get(
            "credentials_scope"
        ) or os.environ.get("DATABRICKS_SECRET_SCOPE", "quintoandar")

        token_payload_extras = auth_config.get("token_payload_extras") or {}
        expires_in_field = auth_config.get("expires_in_field", "expires_in")
        token_request_format = auth_config.get(
            "token_request_format", "form_basic_auth"
        )
        access_token_field = auth_config.get("access_token_field", "access_token")
        http_user_agent = self.get_http_user_agent()

        auth_handler = BasicAuthOAuth2ClientCredentials(
            databricks_scope=databricks_scope,
            secret_key=secret_key,
            token_url=token_url,
            client_id_field=client_id_field,
            client_secret_field=client_secret_field,
            token_payload_extras=token_payload_extras,
            expires_at_field=expires_at_field,
            expires_in_field=expires_in_field,
            fallback_token_expiration_seconds=fallback_token_expiration_seconds,
            token_request_format=token_request_format,
            access_token_field=access_token_field,
            http_user_agent=http_user_agent,
        )

        auth_handler.apply_auth(client.session)

        client.session.headers.update({"Accept": "application/json"})

        LOGGER.info("OAuth2 Client Credentials authentication configured")

    def _apply_basic_authentication(
        self, client: BaseAPIClient, auth_config: Dict[str, Any]
    ):
        """
        Applies Basic Authentication to the client.

        This method configures Basic Authentication for the API client.
        It retrieves the secret key from the authentication configuration and uses
        the BasicAuth handler to manage authentication headers.

        The secret can contain:
        - A single "api_token" field (Base64-encoded token ready to use)
        - Or "username" and "password" fields (will be encoded as username:password)

        Args:
            client: The API client to configure with authentication
            auth_config: Authentication configuration from YAML containing secret_key,
                        and optional token_field, username_field, password_field

        Raises:
            ValueError: If required configuration is missing
        """
        secret_key = auth_config.get("secret_key")
        if not secret_key:
            raise ValueError("'secret_key' is required for basic authentication")

        databricks_scope = self.workflow_config.get(
            "credentials_scope"
        ) or os.environ.get("DATABRICKS_SECRET_SCOPE", "quintoandar")
        token_field = auth_config.get("token_field", "api_token")
        username_field = auth_config.get("username_field")
        password_field = auth_config.get("password_field")

        auth_handler = BasicAuth(
            databricks_scope=databricks_scope,
            secret_key=secret_key,
            token_field=token_field,
            username_field=username_field,
            password_field=password_field,
        )
        auth_handler.apply_auth(client.session)

        client.session.headers.update({"Accept": "application/json"})

        LOGGER.info("Basic Auth authentication configured")

    def _apply_api_key_authentication(
        self, client: BaseAPIClient, auth_config: Dict[str, Any]
    ):
        """
        Applies API Key authentication to the client.

        This method configures API Key authentication for the API client. The API key
        is loaded from Databricks Secrets and can be applied either as an HTTP header
        or as a query parameter, depending on the API requirements.

        The secret must contain an API key field (default: `api_key`). The location
        can be configured as:
        - `header`: Sets the API key as an HTTP header (default header name: `x-api-key`)
        - `query_param`: Appends the API key as a query parameter (default param name: `token`)

        Args:
            client: The API client to configure with authentication
            auth_config: Authentication configuration from YAML containing:
                - secret_key (required): Databricks secret key containing the API key
                - api_key_field (optional, default: "api_key"): Field name in secret JSON
                - location (optional, default: "header"): "header" or "query_param"
                - header_name (optional, default: "x-api-key"): Header name when using header location
                - query_param_name (optional, default: "token"): Query param name when using query_param location

        Raises:
            ValueError: If secret_key is not provided in the configuration
        """
        secret_key = auth_config.get("secret_key")
        if not secret_key:
            raise ValueError("'secret_key' is required for api_key authentication")

        databricks_scope = self.workflow_config.get(
            "credentials_scope"
        ) or os.environ.get("DATABRICKS_SECRET_SCOPE", "quintoandar")

        api_key_field = auth_config.get("api_key_field", "api_key")
        location = auth_config.get("location", "header")
        header_name = auth_config.get("header_name", "x-api-key")
        query_param_name = auth_config.get("query_param_name", "token")

        auth_handler = APIKeyAuth(
            databricks_scope=databricks_scope,
            secret_key=secret_key,
            api_key_field=api_key_field,
            location=location,
            header_name=header_name,
            query_param_name=query_param_name,
        )
        auth_handler.apply_auth(client.session)
        client.session.headers.update({"Accept": "application/json"})
        LOGGER.info("API key authentication configured")

    def create_paginator(
        self,
        client: BaseAPIClient,
        endpoint: str,
        initial_params: Dict[str, Any],
        json_body: Optional[Dict[str, Any]] = None,
    ) -> Optional[BasePaginator]:
        """
        Creates a paginator based on the pagination strategy configuration.

        This method checks for pagination configuration at both table and workflow levels,
        with table-level configuration taking precedence. Pagination can be defined as:
        - Direct key in table_config or workflow_config (e.g., `pagination: {...}`)
        - Within api_policies at table or workflow level (e.g., `api_policies.pagination: {...}`)

        If pagination is configured, it instantiates the appropriate paginator based on the
        strategy. Supports cursor-based pagination (Point-In-Time style), offset/limit pagination,
        or returns None if no pagination is required.

        Args:
            client: The configured API client with authentication applied
            endpoint: The API endpoint path to paginate
            initial_params: Initial query parameters for the first page request
            json_body: Resolved request body for ``http_method: post`` tables
                (see ``get_request_body``); only ``page_per_page`` supports POST.

        Returns:
            Optional[BasePaginator]: Configured paginator instance if pagination is enabled,
                                    None if no pagination strategy is configured

        Raises:
            ValueError: If the pagination strategy is not supported, or if
                ``http_method: post`` is combined with a strategy other than
                ``page_per_page``
        """
        workflow_api_policies = self.workflow_config.get("api_policies", {})
        table_api_policies = self.table_config.get("api_policies", {})

        table_pagination = self.table_config.get(
            "pagination"
        ) or table_api_policies.get("pagination")
        workflow_pagination = self.workflow_config.get(
            "pagination"
        ) or workflow_api_policies.get("pagination")

        pagination_config = table_pagination or workflow_pagination

        if pagination_config is None:
            LOGGER.info("No pagination configuration found. Fetching single page.")
            return None

        if pagination_config == {}:
            raise ValueError(
                "Pagination strategy is required and cannot be empty. "
                "Supported strategies: cursor, offset_limit, page_per_page, none"
            )

        strategy = pagination_config.get("strategy")
        if not strategy or strategy == "":
            raise ValueError(
                "Pagination strategy is required and cannot be empty. "
                "Supported strategies: cursor, offset_limit, page_per_page, none"
            )

        if self.get_http_method() == HttpMethodEnum.POST.value and strategy not in (
            PaginationStrategyEnum.PAGE_PER_PAGE.value,
            PaginationStrategyEnum.NONE.value,
        ):
            raise ValueError(
                f"http_method 'post' is not supported with pagination strategy '{strategy}'. "
                "Use page_per_page or none."
            )

        if strategy == PaginationStrategyEnum.CURSOR.value:
            return self._create_cursor_paginator(
                client, endpoint, initial_params, pagination_config
            )
        elif strategy == PaginationStrategyEnum.OFFSET_LIMIT.value:
            return self._create_offset_limit_paginator(
                client, endpoint, initial_params, pagination_config
            )
        elif strategy == PaginationStrategyEnum.PAGE_PER_PAGE.value:
            return self._create_page_per_page_paginator(
                client, endpoint, initial_params, pagination_config, json_body
            )
        elif strategy == PaginationStrategyEnum.NONE.value:
            LOGGER.info("No pagination strategy configured. Fetching single page.")
            return None
        else:
            raise ValueError(
                f"Pagination strategy '{strategy}' not supported. "
                "Supported strategies: cursor, offset_limit, page_per_page, none"
            )

    def _create_cursor_paginator(
        self,
        client: BaseAPIClient,
        endpoint: str,
        initial_params: Dict[str, Any],
        pagination_config: Dict[str, Any],
    ) -> CursorPaginator:
        """
        Creates a CursorPaginator for Point-In-Time pagination (Greenhouse Audit Log style).

        This method configures a CursorPaginator for cursor pagination.

        Point-In-Time (PIT) APIs send cursor, context, and page size via HTTP
        headers (the loader default). Query-param cursor APIs set
        ``cursor_location`` / ``context_location`` / ``page_size_location`` to
        ``param`` in pagination YAML. The paginator is configured with rate
        limiting delays if specified, and includes automatic retry logic for
        expired Point-In-Time contexts. The extract_results function defaults
        to extracting data from the "results" array in the API response.

        Args:
            client: The configured API client with authentication applied
            endpoint: The API endpoint path to paginate
            initial_params: Initial query parameters for the first page request
            pagination_config: Pagination configuration from YAML containing cursor_param,
                             cursor_response_path, context_param, context_response_path,
                             page_size_param, and page_size

        Returns:
            CursorPaginator: Fully configured paginator instance with Point-In-Time support
        """
        workflow_api_policies = self.workflow_config.get("api_policies", {})
        table_api_policies = self.table_config.get("api_policies", {})

        workflow_rate_limiting = workflow_api_policies.get("rate_limiting", {})
        table_rate_limiting = table_api_policies.get("rate_limiting", {})
        rate_limiting = {}
        rate_limiting.update(workflow_rate_limiting)
        rate_limiting.update(table_rate_limiting)

        delay_seconds = rate_limiting.get("delay_seconds", 0.0)

        cursor_param = pagination_config.get("cursor_param", "Search-After")
        cursor_location = pagination_config.get("cursor_location", "header")
        cursor_response_path = pagination_config.get(
            "cursor_response_path", "paging.next_search_after"
        )

        context_param = pagination_config.get("context_param", "Pit-Id")
        context_location = pagination_config.get("context_location", "header")
        context_response_path = pagination_config.get(
            "context_response_path", "paging.pit_id"
        )

        page_size_param = pagination_config.get("page_size_param", "Size")
        page_size_location = pagination_config.get("page_size_location", "header")
        page_size = pagination_config.get("page_size", 500)

        results_response_path = pagination_config.get("results_response_path")
        if results_response_path:

            def extract_results(data):
                if isinstance(data, dict):
                    return data.get(results_response_path, [])
                return []

        else:
            extract_results = None

        return CursorPaginator(
            client=client,
            endpoint=endpoint,
            initial_params=initial_params,
            cursor_param=cursor_param,
            cursor_location=cursor_location,
            cursor_response_path=cursor_response_path,
            context_param=context_param,
            context_location=context_location,
            context_response_path=context_response_path,
            page_size_param=page_size_param,
            page_size_location=page_size_location,
            page_size=page_size,
            extract_results=extract_results,
            page_delay=delay_seconds if delay_seconds > 0 else None,
            retry_on_context_expiration=True,
            max_context_retries=3,
        )

    def _create_offset_limit_paginator(
        self,
        client: BaseAPIClient,
        endpoint: str,
        initial_params: Dict[str, Any],
        pagination_config: Dict[str, Any],
    ) -> OffsetLimitPaginator:
        """
        Creates an OffsetLimitPaginator for offset/limit pagination.

        This method configures an OffsetLimitPaginator for offset/limit pagination strategy,
        commonly used by APIs like Oracle HCM and LinkedIn. The paginator increments the offset
        by the page_size for each subsequent page until no more results are returned. Rate limiting
        delays can be applied between page requests if specified.

        Args:
            client: The configured API client with authentication applied
            endpoint: The API endpoint path to paginate
            initial_params: Initial query parameters for the first page request
            pagination_config: Pagination configuration from YAML containing limit_param,
                             offset_param, and page_size

        Returns:
            OffsetLimitPaginator: Fully configured paginator instance with offset/limit support
        """
        workflow_api_policies = self.workflow_config.get("api_policies", {})
        table_api_policies = self.table_config.get("api_policies", {})

        workflow_rate_limiting = workflow_api_policies.get("rate_limiting", {})
        table_rate_limiting = table_api_policies.get("rate_limiting", {})
        rate_limiting = {}
        rate_limiting.update(workflow_rate_limiting)
        rate_limiting.update(table_rate_limiting)

        delay_seconds = rate_limiting.get("delay_seconds", 0.0)

        limit_param = pagination_config.get("limit_param", "limit")
        offset_param = pagination_config.get("offset_param", "offset")
        page_size = pagination_config.get("page_size", 100)

        if not isinstance(page_size, int) or page_size <= 0:
            raise ValueError(f"page_size must be a positive integer, got {page_size}")

        LOGGER.info(
            "Creating OffsetLimitPaginator for endpoint '%s' with "
            "limit_param=%s, offset_param=%s, page_size=%d",
            endpoint,
            limit_param,
            offset_param,
            page_size,
        )

        return OffsetLimitPaginator(
            client=client,
            endpoint=endpoint,
            initial_params=initial_params,
            limit_param=limit_param,
            offset_param=offset_param,
            page_size=page_size,
            page_delay=delay_seconds if delay_seconds > 0 else None,
        )

    def _create_page_per_page_paginator(
        self,
        client: BaseAPIClient,
        endpoint: str,
        initial_params: Dict[str, Any],
        pagination_config: Dict[str, Any],
        json_body: Optional[Dict[str, Any]] = None,
    ) -> PagePerPagePaginator:
        """
        Creates a PagePerPagePaginator for 1-based ``page`` / ``per_page`` style APIs.

        Optional pagination keys: ``total_pages_path`` (dot path to the page count in
        the response, e.g. ``pagination.totalPages``) and ``envelope_fields`` (root
        response keys copied onto every row). With table ``http_method: post``, the
        page and page size are sent in ``json_body``.
        """
        workflow_api_policies = self.workflow_config.get("api_policies", {})
        table_api_policies = self.table_config.get("api_policies", {})

        workflow_rate_limiting = workflow_api_policies.get("rate_limiting", {})
        table_rate_limiting = table_api_policies.get("rate_limiting", {})
        rate_limiting = {}
        rate_limiting.update(workflow_rate_limiting)
        rate_limiting.update(table_rate_limiting)

        delay_seconds = rate_limiting.get("delay_seconds", 0.0)

        page_param = pagination_config.get("page_param", "page")
        per_page_param = pagination_config.get("per_page_param", "per_page")
        page_size = pagination_config.get("page_size", 100)

        if not isinstance(page_size, int) or page_size <= 0:
            raise ValueError(f"page_size must be a positive integer, got {page_size}")

        results_response_path = pagination_config.get("results_response_path")
        if results_response_path:

            def extract_results(data):
                if isinstance(data, dict):
                    return data.get(results_response_path, [])
                return []

        else:
            extract_results = None

        LOGGER.info(
            "Creating PagePerPagePaginator for endpoint '%s' with "
            "page_param=%s, per_page_param=%s, page_size=%d",
            endpoint,
            page_param,
            per_page_param,
            page_size,
        )

        return PagePerPagePaginator(
            client=client,
            endpoint=endpoint,
            initial_params=initial_params,
            page_param=page_param,
            per_page_param=per_page_param,
            page_size=page_size,
            page_delay=delay_seconds if delay_seconds > 0 else None,
            extract_results=extract_results,
            http_method=self.get_http_method(),
            json_body=json_body,
            total_pages_path=pagination_config.get("total_pages_path"),
            envelope_fields=pagination_config.get("envelope_fields"),
        )

    def get_endpoint_path(self) -> str:
        """
        Returns the endpoint path for the table.

        Returns:
            str: The endpoint path

        Raises:
            ValueError: If endpoint_path is not configured
        """
        endpoint_path = self.table_config.get("endpoint_path")
        if not endpoint_path:
            raise ValueError("'endpoint_path' is required in table configuration")
        return endpoint_path

    def get_initial_params(
        self, load_start_date: str, load_end_date: str
    ) -> Dict[str, Any]:
        """
        Builds initial query parameters for the API request, replacing date placeholders.

        This method processes params from table configuration and replaces date placeholders
        (load_start_date, load_end_date) with formatted timestamps. The date format can be
        customized via the 'date_format' configuration in table_customization. If not specified,
        ISO-8601 format is used as default. If params are not provided, it defaults to adding
        after_time and before_time parameters.

        Args:
            load_start_date: Start date string in YYYY-MM-DD format
            load_end_date: End date string in YYYY-MM-DD format

        Returns:
            Dict[str, Any]: Dictionary of query parameters with date placeholders replaced by
                           formatted timestamps.
        """
        if "params" in self.table_config:
            table_params = self.table_config.get("params") or {}
            return self._resolve_date_placeholders(
                table_params, load_start_date, load_end_date
            )

        return self._resolve_date_placeholders(
            {"after_time": "load_start_date", "before_time": "load_end_date"},
            load_start_date,
            load_end_date,
        )

    def get_http_method(self) -> str:
        """
        Returns the table's HTTP method for data requests (``get`` or ``post``).

        Raises:
            ValueError: If ``http_method`` is not a supported value.
        """
        http_method = str(self.table_config.get("http_method", "get")).lower()
        if http_method not in HttpMethodEnum.get_available_enum_values():
            raise ValueError(
                f"http_method '{http_method}' not supported. "
                f"Supported methods: {HttpMethodEnum.get_available_enum_values()}"
            )
        return http_method

    def get_request_body(
        self, load_start_date: str, load_end_date: str
    ) -> Optional[Dict[str, Any]]:
        """
        Builds the JSON body for ``http_method: post`` tables, replacing date placeholders.

        Values equal to ``load_start_date`` / ``load_end_date`` are formatted with the
        same ``date_format`` as ``params``. Date offsets (``load_end_date+1``) are not
        resolved in the body.

        Returns:
            Optional[Dict[str, Any]]: Resolved body, or None when ``body`` is not configured.

        Raises:
            ValueError: If ``body`` is not a mapping.
        """
        body = self.table_config.get("body")
        if body is None:
            return None
        if not isinstance(body, dict):
            raise ValueError("'body' must be a mapping of JSON field name to value")
        return self._resolve_date_placeholders(body, load_start_date, load_end_date)

    def _get_date_format(self) -> Optional[str]:
        table_date_format = self.table_config.get("date_format")
        if table_date_format == "":
            raise ValueError(
                "date_format cannot be an empty string. "
                "Use ISO-8601 format by omitting date_format or specify a valid strftime format."
            )
        return (
            table_date_format
            if table_date_format
            else self.workflow_config.get("date_format")
            or self.workflow_config.get("date_format_mask")
        )

    def _resolve_date_placeholders(
        self, values: Dict[str, Any], load_start_date: str, load_end_date: str
    ) -> Dict[str, Any]:
        """
        Replaces ``load_start_date`` / ``load_end_date`` values with formatted dates.

        A placeholder whose load date is empty is dropped from the result.
        """
        date_format = self._get_date_format()
        placeholder_dates = {
            "load_start_date": (load_start_date, START_OF_DAY_SUFFIX),
            "load_end_date": (load_end_date, END_OF_DAY_SUFFIX),
        }
        resolved: Dict[str, Any] = {}
        for key, value in values.items():
            if isinstance(value, str) and value in DATE_PLACEHOLDERS:
                load_date, time_suffix = placeholder_dates[value]
                if load_date:
                    resolved[key] = format_load_date(
                        load_date, date_format, time_suffix
                    )
            else:
                resolved[key] = value
        return resolved

    def get_date_column_for_partitioning(self) -> Optional[str]:
        """
        Returns the date column name for partitioning if configured.

        Checks table_config first, then workflow_config as fallback.

        Returns:
            Optional[str]: Date column name or None
        """
        return self.table_config.get("date_filter_column") or self.workflow_config.get(
            "date_filter_column"
        )

    def get_payload_column_name(self) -> str:
        """
        Returns the payload column name, defaulting to "payload" if not configured.

        This method checks for payload_column_name in table_config first (table-level
        takes precedence), then in workflow_config. If neither is specified, it
        defaults to "payload".

        Returns:
            str: The payload column name to use
        """
        payload_column = (
            self.table_config.get("payload_column_name")
            or self.workflow_config.get("payload_column_name")
            or "payload"
        )
        return payload_column

    def get_id_expansion_config(self) -> Optional[Dict[str, Any]]:
        """
        Returns the id_expansion configuration if present, or None.

        id_expansion enables fan-out fetching: one API call per entity ID extracted
        from an already-ingested raw source table. Required keys are source_table,
        id_field, and exactly one of param_name (query param), path_param (URL path
        segment), or json_body_field (POST JSON property holding the entity id).
        Optional correlation_field sets the response JSON key used to stamp each row
        with the fan-out id (defaults to id_field, which must exist on the source
        payload for ID extraction).

        Example YAML:
            id_expansion:
              source_table: employees
              id_field: uuid
              param_name: employeeUuid

        Returns:
            Optional[Dict[str, Any]]: id_expansion config dict, or None if not configured.
        """
        return self.table_config.get("id_expansion") or None
