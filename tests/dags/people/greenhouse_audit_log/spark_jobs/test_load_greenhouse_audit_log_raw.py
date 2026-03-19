import json
import sys
import unittest
from unittest.mock import MagicMock, patch

# Mock PySpark and all its submodules before any imports
mock_pyspark = MagicMock()
sys.modules["pyspark"] = mock_pyspark
sys.modules["pyspark.conf"] = MagicMock()
sys.modules["pyspark.sql"] = MagicMock()
sys.modules["pyspark.sql.functions"] = MagicMock()
sys.modules["pyspark.sql.types"] = MagicMock()
sys.modules["pyspark.sql.dataframe"] = MagicMock()
sys.modules["pyspark.context"] = MagicMock()

# Mock other dependencies that require Spark
sys.modules["bietlejuice.jobs.common.helpers"] = MagicMock()
sys.modules["bietlejuice.jobs.common.raw_layer_loader"] = MagicMock()
sys.modules["quintoandar_logger"] = MagicMock()

from dags.people.greenhouse_audit_log.spark_jobs.load_greenhouse_audit_log_raw import (  # noqa: E402
    GreenhouseAuditLogAPI,
    InvalidCursorResumeError,
    main,
    format_search_after_cursor,
    OAUTH_TOKEN_URL,
    DATABRICKS_SCOPE,
    APIEnum,
    TOKEN_EXPIRATION_SECONDS,
    PAGE_SIZE,
    PAGINATION_RATE_LIMIT_DELAY,
    DEFAULT_PARTITION_COLUMN,
    FILTER_PLACEHOLDER_START_DATE,
    FILTER_PLACEHOLDER_END_DATE,
)


class TestFormatSearchAfterCursor(unittest.TestCase):
    """Tests for the format_search_after_cursor function."""

    def test_format_cursor_none(self):
        """Test that None input returns None."""
        result = format_search_after_cursor(None)
        self.assertIsNone(result)

    def test_format_cursor_list_with_two_elements(self):
        """Test formatting a list with exactly 2 elements."""
        cursor = [1769113670314, "8a7243fba6e775b3822a60a254563238"]
        result = format_search_after_cursor(cursor)
        self.assertEqual(result, "1769113670314,8a7243fba6e775b3822a60a254563238")

    def test_format_cursor_list_with_three_elements(self):
        """Test formatting a list with 3 elements (only first 2 should be used)."""
        cursor = [
            1769113670314,
            "8a7243fba6e775b3822a60a254563238",
            "d01384f1317d57c567b3f6e06c7f0827",
        ]
        result = format_search_after_cursor(cursor)
        self.assertEqual(result, "1769113670314,8a7243fba6e775b3822a60a254563238")

    def test_format_cursor_list_with_one_element(self):
        """Test that list with 1 element returns None (API requires integer,string)."""
        cursor = [1769113670314]
        result = format_search_after_cursor(cursor)
        self.assertIsNone(result)

    def test_format_cursor_empty_list(self):
        """Test that empty list returns None."""
        result = format_search_after_cursor([])
        self.assertIsNone(result)

    def test_format_cursor_list_with_empty_second_element(self):
        """Test that list with empty string as second element returns None."""
        cursor = [1771866937368, ""]
        result = format_search_after_cursor(cursor)
        self.assertIsNone(result)

    def test_format_cursor_list_with_none_second_element(self):
        """Test that list with None as second element returns None."""
        cursor = [1771866937368, None]
        result = format_search_after_cursor(cursor)
        self.assertIsNone(result)

    def test_format_cursor_string_with_two_components(self):
        """Test formatting a string with 2 components."""
        cursor = "1769113670314,8a7243fba6e775b3822a60a254563238"
        result = format_search_after_cursor(cursor)
        self.assertEqual(result, "1769113670314,8a7243fba6e775b3822a60a254563238")

    def test_format_cursor_string_with_three_components(self):
        """Test formatting a string with 3 components (only first 2 should be used)."""
        cursor = "1769113670314,8a7243fba6e775b3822a60a254563238,d01384f1317d57c567b3f6e06c7f0827"
        result = format_search_after_cursor(cursor)
        self.assertEqual(result, "1769113670314,8a7243fba6e775b3822a60a254563238")

    def test_format_cursor_string_with_spaces(self):
        """Test formatting a string with spaces around components."""
        cursor = "1769113670314, 8a7243fba6e775b3822a60a254563238, d01384f1317d57c567b3f6e06c7f0827"
        result = format_search_after_cursor(cursor)
        self.assertEqual(result, "1769113670314,8a7243fba6e775b3822a60a254563238")

    def test_format_cursor_string_single_component(self):
        """Test that string with single component returns None (API requires integer,string)."""
        cursor = "1769113670314"
        result = format_search_after_cursor(cursor)
        self.assertIsNone(result)

    def test_format_cursor_integer(self):
        """Test that integer value returns None (API requires integer,string)."""
        cursor = 1769113670314
        result = format_search_after_cursor(cursor)
        self.assertIsNone(result)


class TestGreenhouseAuditLogAPIExtractPaginationState(unittest.TestCase):
    """Tests for the GreenhouseAuditLogAPI._extract_pagination_state method."""

    @patch.object(GreenhouseAuditLogAPI, "_apply_authentication")
    @patch.object(GreenhouseAuditLogAPI, "_process_filters")
    def test_extract_pagination_state_with_list_cursor(
        self, mock_process_filters, mock_auth
    ):
        """Test extraction with cursor as a list of 3 elements."""
        job_args = {"endpoint": "events", "base_filters": {}}
        api_client = GreenhouseAuditLogAPI(job_args)

        data = {
            "paging": {
                "next_search_after": [
                    1769113670314,
                    "8a7243fba6e775b3822a60a254563238",
                    "d01384f1317d57c567b3f6e06c7f0827",
                ],
                "pit_id": "pit123",
            }
        }

        state = api_client._extract_pagination_state(data)

        self.assertEqual(
            state["cursor"], "1769113670314,8a7243fba6e775b3822a60a254563238"
        )
        self.assertEqual(state["context"], "pit123")

    @patch.object(GreenhouseAuditLogAPI, "_apply_authentication")
    @patch.object(GreenhouseAuditLogAPI, "_process_filters")
    def test_extract_pagination_state_with_string_cursor(
        self, mock_process_filters, mock_auth
    ):
        """Test extraction with cursor as a comma-separated string."""
        job_args = {"endpoint": "events", "base_filters": {}}
        api_client = GreenhouseAuditLogAPI(job_args)

        data = {
            "paging": {
                "next_search_after": "1769113670314,hash1,hash2",
                "pit_id": "pit456",
            }
        }

        state = api_client._extract_pagination_state(data)

        self.assertEqual(state["cursor"], "1769113670314,hash1")
        self.assertEqual(state["context"], "pit456")

    @patch.object(GreenhouseAuditLogAPI, "_apply_authentication")
    @patch.object(GreenhouseAuditLogAPI, "_process_filters")
    def test_extract_pagination_state_no_cursor(self, mock_process_filters, mock_auth):
        """Test extraction when cursor is None."""
        job_args = {"endpoint": "events", "base_filters": {}}
        api_client = GreenhouseAuditLogAPI(job_args)

        data = {"paging": {"next_search_after": None, "pit_id": "pit789"}}

        state = api_client._extract_pagination_state(data)

        self.assertNotIn("cursor", state)
        self.assertEqual(state["context"], "pit789")

    @patch.object(GreenhouseAuditLogAPI, "_apply_authentication")
    @patch.object(GreenhouseAuditLogAPI, "_process_filters")
    def test_extract_pagination_state_empty_paging(
        self, mock_process_filters, mock_auth
    ):
        """Test extraction when paging object is empty."""
        job_args = {"endpoint": "events", "base_filters": {}}
        api_client = GreenhouseAuditLogAPI(job_args)

        data = {"paging": {}}

        state = api_client._extract_pagination_state(data)

        self.assertEqual(state, {})

    @patch.object(GreenhouseAuditLogAPI, "_apply_authentication")
    @patch.object(GreenhouseAuditLogAPI, "_process_filters")
    def test_extract_pagination_state_invalid_cursor_with_results_raises(
        self, mock_process_filters, mock_auth
    ):
        """Test that invalid cursor with results raises InvalidCursorResumeError."""
        job_args = {"endpoint": "events", "base_filters": {}}
        api_client = GreenhouseAuditLogAPI(job_args)

        data = {
            "paging": {"next_search_after": [1771866937368], "pit_id": "pit123"},
            "results": [{"event_time": "2024-01-01T00:00:00Z"}],
        }

        with self.assertRaises(InvalidCursorResumeError) as ctx:
            api_client._extract_pagination_state(data)

        self.assertIn("1771866937368", str(ctx.exception))

    @patch.object(GreenhouseAuditLogAPI, "_apply_authentication")
    @patch.object(GreenhouseAuditLogAPI, "_process_filters")
    def test_extract_pagination_state_invalid_cursor_empty_results_no_raise(
        self, mock_process_filters, mock_auth
    ):
        """Test that invalid cursor with empty results does not raise (last page)."""
        job_args = {"endpoint": "events", "base_filters": {}}
        api_client = GreenhouseAuditLogAPI(job_args)

        data = {
            "paging": {"next_search_after": [1771866937368], "pit_id": "pit123"},
            "results": [],
        }

        state = api_client._extract_pagination_state(data)

        self.assertNotIn("cursor", state)
        self.assertEqual(state["context"], "pit123")


class TestGreenhouseAuditLogAPIPitIdResume(unittest.TestCase):
    """Tests for Pit_Id expiration and resume logic."""

    @patch.object(GreenhouseAuditLogAPI, "_apply_authentication")
    @patch.object(GreenhouseAuditLogAPI, "_process_filters")
    def test_is_pit_id_expired_detects_expiration(self, mock_process_filters, mock_auth):
        """Test _is_pit_id_expired detects Greenhouse Pit_Id expiration error."""
        job_args = {"endpoint": "events", "base_filters": {}}
        api_client = GreenhouseAuditLogAPI(job_args)

        error = Exception('Bad Request: {"error":"The Pit_Id has expired. Remove it from the subsequent search."}')
        self.assertTrue(api_client._is_pit_id_expired(error))

    @patch.object(GreenhouseAuditLogAPI, "_apply_authentication")
    @patch.object(GreenhouseAuditLogAPI, "_process_filters")
    def test_is_pit_id_expired_rejects_other_errors(self, mock_process_filters, mock_auth):
        """Test _is_pit_id_expired returns False for non-Pit_Id errors."""
        job_args = {"endpoint": "events", "base_filters": {}}
        api_client = GreenhouseAuditLogAPI(job_args)

        self.assertFalse(api_client._is_pit_id_expired(Exception("Network error")))
        self.assertFalse(api_client._is_pit_id_expired(Exception("401 Unauthorized")))

    @patch.object(GreenhouseAuditLogAPI, "_apply_authentication")
    @patch.object(GreenhouseAuditLogAPI, "_process_filters")
    def test_get_max_event_time_returns_max(self, mock_process_filters, mock_auth):
        """Test _get_max_event_time returns the latest event_time."""
        job_args = {"endpoint": "events", "base_filters": {}}
        api_client = GreenhouseAuditLogAPI(job_args)

        results = [
            {"event_time": "2025-01-15T10:00:00Z"},
            {"event_time": "2025-01-16T11:00:00Z"},
            {"event_time": "2025-01-15T09:00:00Z"},
        ]
        self.assertEqual(
            api_client._get_max_event_time(results), "2025-01-16T11:00:00Z"
        )

    @patch.object(GreenhouseAuditLogAPI, "_apply_authentication")
    @patch.object(GreenhouseAuditLogAPI, "_process_filters")
    def test_get_max_event_time_ignores_none(self, mock_process_filters, mock_auth):
        """Test _get_max_event_time ignores records without event_time."""
        job_args = {"endpoint": "events", "base_filters": {}}
        api_client = GreenhouseAuditLogAPI(job_args)

        results = [
            {"id": "1"},
            {"event_time": "2025-01-15T10:00:00Z"},
        ]
        self.assertEqual(
            api_client._get_max_event_time(results), "2025-01-15T10:00:00Z"
        )

    @patch.object(GreenhouseAuditLogAPI, "_apply_authentication")
    @patch.object(GreenhouseAuditLogAPI, "_process_filters")
    def test_get_max_event_time_returns_none_for_empty(self, mock_process_filters, mock_auth):
        """Test _get_max_event_time returns None when no event_times."""
        job_args = {"endpoint": "events", "base_filters": {}}
        api_client = GreenhouseAuditLogAPI(job_args)

        self.assertIsNone(api_client._get_max_event_time([]))
        self.assertIsNone(api_client._get_max_event_time([{"id": "1"}, {"id": "2"}]))

    @patch.object(GreenhouseAuditLogAPI, "_apply_authentication")
    @patch.object(GreenhouseAuditLogAPI, "_process_filters")
    def test_should_resume_on_error_invalid_cursor(self, mock_process_filters, mock_auth):
        """Test _should_resume_on_error returns True for InvalidCursorResumeError."""
        job_args = {"endpoint": "events", "base_filters": {}}
        api_client = GreenhouseAuditLogAPI(job_args)

        self.assertTrue(
            api_client._should_resume_on_error(
                InvalidCursorResumeError("Invalid cursor")
            )
        )

    @patch.object(GreenhouseAuditLogAPI, "_apply_authentication")
    @patch.object(GreenhouseAuditLogAPI, "_process_filters")
    def test_should_resume_on_error_pit_id_expired(self, mock_process_filters, mock_auth):
        """Test _should_resume_on_error returns True for Pit_Id expiration."""
        job_args = {"endpoint": "events", "base_filters": {}}
        api_client = GreenhouseAuditLogAPI(job_args)

        self.assertTrue(
            api_client._should_resume_on_error(
                Exception("The Pit_Id has expired. Remove it from the subsequent search.")
            )
        )


class TestGreenhouseAuditLogAPIInit(unittest.TestCase):
    """Tests for the GreenhouseAuditLogAPI.__init__ method."""

    @patch.object(GreenhouseAuditLogAPI, "_apply_authentication")
    @patch.object(GreenhouseAuditLogAPI, "_process_filters")
    def test_init_with_dict_filters(self, mock_process_filters, mock_auth):
        """Test initialization with filters as dictionary."""
        job_args = {
            "endpoint": "events",
            "base_filters": {"actor.user_id": "123", "paging": "true"},
            "load_start_date": "2025-01-01",
            "load_end_date": "2025-01-31",
        }

        api_client = GreenhouseAuditLogAPI(job_args)

        self.assertEqual(api_client.endpoint, "events")
        self.assertEqual(
            api_client.base_filters, {"actor.user_id": "123", "paging": "true"}
        )
        self.assertEqual(api_client.load_start_date, "2025-01-01")
        self.assertEqual(api_client.load_end_date, "2025-01-31")
        mock_auth.assert_called_once()
        mock_process_filters.assert_called_once()

    @patch.object(GreenhouseAuditLogAPI, "_apply_authentication")
    @patch.object(GreenhouseAuditLogAPI, "_process_filters")
    def test_init_with_json_string_filters(self, mock_process_filters, mock_auth):
        """Test initialization with filters as JSON string."""
        filters_dict = {"actor.user_id": "123", "paging": "true"}
        job_args = {
            "endpoint": "events",
            "base_filters": json.dumps(filters_dict),
            "load_start_date": "2025-01-01",
            "load_end_date": "2025-01-31",
        }

        api_client = GreenhouseAuditLogAPI(job_args)

        self.assertEqual(api_client.base_filters, filters_dict)
        mock_auth.assert_called_once()
        mock_process_filters.assert_called_once()

    @patch.object(GreenhouseAuditLogAPI, "_apply_authentication")
    @patch.object(GreenhouseAuditLogAPI, "_process_filters")
    def test_init_with_invalid_json_string(self, mock_process_filters, mock_auth):
        """Test initialization with invalid JSON string raises error."""
        job_args = {
            "endpoint": "events",
            "base_filters": "invalid{json",
            "load_start_date": "2025-01-01",
            "load_end_date": "2025-01-31",
        }

        with self.assertRaises(json.JSONDecodeError):
            GreenhouseAuditLogAPI(job_args)

        mock_auth.assert_not_called()
        mock_process_filters.assert_not_called()

    @patch.object(GreenhouseAuditLogAPI, "_apply_authentication")
    @patch.object(GreenhouseAuditLogAPI, "_process_filters")
    def test_init_with_empty_filters(self, mock_process_filters, mock_auth):
        """Test initialization with no filters provided."""
        job_args = {
            "endpoint": "events",
            "load_start_date": "2025-01-01",
            "load_end_date": "2025-01-31",
        }

        api_client = GreenhouseAuditLogAPI(job_args)

        self.assertEqual(api_client.base_filters, {})
        mock_auth.assert_called_once()
        mock_process_filters.assert_called_once()


class TestGreenhouseAuditLogAPIAuthentication(unittest.TestCase):
    """Tests for the GreenhouseAuditLogAPI._apply_authentication method."""

    @patch.object(GreenhouseAuditLogAPI, "_process_filters")
    @patch(
        "dags.people.greenhouse_audit_log.spark_jobs.load_greenhouse_audit_log_raw.BasicAuthOAuth2ClientCredentials"
    )
    def test_apply_authentication(self, mock_auth_class, mock_process_filters):
        """Test that authentication handler is correctly applied."""
        mock_auth_handler = MagicMock()
        mock_auth_class.return_value = mock_auth_handler

        job_args = {
            "endpoint": "events",
            "base_filters": {},
            "load_start_date": "2025-01-01",
            "load_end_date": "2025-01-31",
        }

        api_client = GreenhouseAuditLogAPI(job_args)

        # Verify auth handler was created with correct params
        mock_auth_class.assert_called_once_with(
            databricks_scope=DATABRICKS_SCOPE,
            secret_key=APIEnum.GREENHOUSE_AUDIT_LOG,
            token_url=OAUTH_TOKEN_URL,
            client_id_field="client_id",
            client_secret_field="client_secret",
            token_payload_extras={"scope": "harvest"},
            expires_at_field="expires_at",
            fallback_token_expiration_seconds=TOKEN_EXPIRATION_SECONDS,
        )

        # Verify auth was applied to session
        mock_auth_handler.apply_auth.assert_called_once_with(api_client.session)

        # Verify Accept header was set
        self.assertEqual(api_client.session.headers.get("Accept"), "application/json")


class TestGreenhouseAuditLogAPIProcessFilters(unittest.TestCase):
    """Tests for the GreenhouseAuditLogAPI._process_filters method."""

    @patch.object(GreenhouseAuditLogAPI, "_apply_authentication")
    def test_process_filters_with_date_placeholders(self, mock_auth):
        """Test filter processing with start and end date placeholders."""
        job_args = {
            "endpoint": "events",
            "base_filters": {
                "occurred_at[gte]": FILTER_PLACEHOLDER_START_DATE,
                "occurred_at[lte]": FILTER_PLACEHOLDER_END_DATE,
                "actor.user_id": "123",
                "paging": "true",
            },
            "load_start_date": "2025-01-15",
            "load_end_date": "2025-01-20",
        }

        api_client = GreenhouseAuditLogAPI(job_args)

        # Verify start date placeholder was replaced
        self.assertEqual(
            api_client.params["occurred_at[gte]"], "2025-01-15T00:00:00Z"
        )
        # Verify end date placeholder was replaced
        self.assertEqual(
            api_client.params["occurred_at[lte]"], "2025-01-20T00:00:00Z"
        )
        # Verify other params remain unchanged
        self.assertEqual(api_client.params["actor.user_id"], "123")
        self.assertEqual(api_client.params["paging"], "true")

    @patch.object(GreenhouseAuditLogAPI, "_apply_authentication")
    def test_process_filters_without_placeholders(self, mock_auth):
        """Test filter processing without date placeholders."""
        job_args = {
            "endpoint": "events",
            "base_filters": {"actor.user_id": "123", "paging": "true"},
            "load_start_date": "2025-01-15",
            "load_end_date": "2025-01-20",
        }

        api_client = GreenhouseAuditLogAPI(job_args)

        # Verify params are unchanged when no placeholders
        self.assertEqual(api_client.params["actor.user_id"], "123")
        self.assertEqual(api_client.params["paging"], "true")
        self.assertNotIn("occurred_at[gte]", api_client.params)
        self.assertNotIn("occurred_at[lte]", api_client.params)

    @patch.object(GreenhouseAuditLogAPI, "_apply_authentication")
    def test_process_filters_adds_paging_if_missing(self, mock_auth):
        """Test that paging=true is added if not present in filters."""
        job_args = {
            "endpoint": "events",
            "base_filters": {"actor.user_id": "123"},
            "load_start_date": "2025-01-15",
            "load_end_date": "2025-01-20",
        }

        api_client = GreenhouseAuditLogAPI(job_args)

        # Verify paging was added
        self.assertEqual(api_client.params["paging"], "true")

    @patch.object(GreenhouseAuditLogAPI, "_apply_authentication")
    def test_process_filters_keeps_existing_paging(self, mock_auth):
        """Test that existing paging parameter is not overwritten."""
        job_args = {
            "endpoint": "events",
            "base_filters": {"actor.user_id": "123", "paging": "false"},
            "load_start_date": "2025-01-15",
            "load_end_date": "2025-01-20",
        }

        api_client = GreenhouseAuditLogAPI(job_args)

        # Verify paging was not changed
        self.assertEqual(api_client.params["paging"], "false")

    @patch.object(GreenhouseAuditLogAPI, "_apply_authentication")
    def test_process_filters_with_missing_dates(self, mock_auth):
        """Test filter processing when load dates are not provided."""
        job_args = {
            "endpoint": "events",
            "base_filters": {
                "occurred_at[gte]": FILTER_PLACEHOLDER_START_DATE,
                "occurred_at[lte]": FILTER_PLACEHOLDER_END_DATE,
                "paging": "true",
            },
        }

        api_client = GreenhouseAuditLogAPI(job_args)

        # Placeholders should remain as-is when dates are not provided
        self.assertEqual(
            api_client.params["occurred_at[gte]"], FILTER_PLACEHOLDER_START_DATE
        )
        self.assertEqual(
            api_client.params["occurred_at[lte]"], FILTER_PLACEHOLDER_END_DATE
        )

    @patch.object(GreenhouseAuditLogAPI, "_apply_authentication")
    def test_process_filters_with_only_start_date(self, mock_auth):
        """Test filter processing when only start date is provided but both placeholders exist."""
        job_args = {
            "endpoint": "events",
            "base_filters": {
                "occurred_at[gte]": FILTER_PLACEHOLDER_START_DATE,
                "occurred_at[lte]": FILTER_PLACEHOLDER_END_DATE,
                "paging": "true",
            },
            "load_start_date": "2025-01-15",
            # "load_end_date" is missing
        }

        api_client = GreenhouseAuditLogAPI(job_args)

        # Verify start date was replaced
        self.assertEqual(
            api_client.params["occurred_at[gte]"], "2025-01-15T00:00:00Z"
        )
        # Verify end date placeholder remained unchanged
        self.assertEqual(
            api_client.params["occurred_at[lte]"], FILTER_PLACEHOLDER_END_DATE
        )

    @patch.object(GreenhouseAuditLogAPI, "_apply_authentication")
    def test_process_filters_with_only_end_date(self, mock_auth):
        """Test filter processing when only end date is provided but both placeholders exist."""
        job_args = {
            "endpoint": "events",
            "base_filters": {
                "occurred_at[gte]": FILTER_PLACEHOLDER_START_DATE,
                "occurred_at[lte]": FILTER_PLACEHOLDER_END_DATE,
                "paging": "true",
            },
            "load_end_date": "2025-01-31",
            # "load_start_date" is missing
        }

        api_client = GreenhouseAuditLogAPI(job_args)

        # Verify start date placeholder remained unchanged
        self.assertEqual(
            api_client.params["occurred_at[gte]"], FILTER_PLACEHOLDER_START_DATE
        )
        # Verify end date was replaced
        self.assertEqual(
            api_client.params["occurred_at[lte]"], "2025-01-31T00:00:00Z"
        )


class TestGreenhouseAuditLogAPIGetAllPaginatedResults(unittest.TestCase):
    """Tests for the GreenhouseAuditLogAPI.get_all_paginated_results method."""

    @patch.object(GreenhouseAuditLogAPI, "_apply_authentication")
    @patch.object(GreenhouseAuditLogAPI, "_process_filters")
    @patch(
        "dags.people.greenhouse_audit_log.spark_jobs.load_greenhouse_audit_log_raw.CursorPaginator"
    )
    def test_get_all_paginated_results_success(
        self, mock_paginator_class, mock_process_filters, mock_auth
    ):
        """Test successful paginated data fetching."""
        # Setup mock paginator
        mock_paginator = MagicMock()
        mock_paginator.fetch_all.return_value = iter(
            [[{"id": 1, "action": "create"}], [{"id": 2, "action": "update"}]]
        )
        mock_paginator_class.return_value = mock_paginator

        job_args = {
            "endpoint": "events",
            "base_filters": {"paging": "true"},
            "load_start_date": "2025-01-01",
            "load_end_date": "2025-01-31",
        }

        api_client = GreenhouseAuditLogAPI(job_args)
        # Manually set params since _process_filters is mocked
        api_client.params = {"paging": "true"}
        results = api_client.get_all_paginated_results()

        # Verify results were aggregated correctly
        self.assertEqual(len(results), 2)
        self.assertEqual(results[0], {"id": 1, "action": "create"})
        self.assertEqual(results[1], {"id": 2, "action": "update"})

        # Verify paginator was created with correct parameters
        mock_paginator_class.assert_called_once()
        call_kwargs = mock_paginator_class.call_args[1]
        self.assertEqual(call_kwargs["client"], api_client)
        self.assertEqual(call_kwargs["endpoint"], "events")
        self.assertEqual(call_kwargs["cursor_param"], "Search-After")
        self.assertEqual(call_kwargs["cursor_location"], "header")
        self.assertEqual(call_kwargs["context_param"], "Pit-Id")
        self.assertEqual(call_kwargs["page_size"], PAGE_SIZE)
        self.assertEqual(call_kwargs["page_delay"], PAGINATION_RATE_LIMIT_DELAY)
        self.assertTrue(call_kwargs["retry_on_context_expiration"])

    @patch.object(GreenhouseAuditLogAPI, "_apply_authentication")
    @patch.object(GreenhouseAuditLogAPI, "_process_filters")
    def test_get_all_paginated_results_no_endpoint(
        self, mock_process_filters, mock_auth
    ):
        """Test that ValueError is raised when endpoint is not defined."""
        job_args = {
            "base_filters": {"paging": "true"},
            "load_start_date": "2025-01-01",
            "load_end_date": "2025-01-31",
        }

        api_client = GreenhouseAuditLogAPI(job_args)
        api_client.endpoint = None

        with self.assertRaises(ValueError) as context:
            api_client.get_all_paginated_results()

        self.assertIn("endpoint", str(context.exception).lower())

    @patch.object(GreenhouseAuditLogAPI, "_apply_authentication")
    @patch.object(GreenhouseAuditLogAPI, "_process_filters")
    @patch(
        "dags.people.greenhouse_audit_log.spark_jobs.load_greenhouse_audit_log_raw.CursorPaginator"
    )
    def test_get_all_paginated_results_empty(
        self, mock_paginator_class, mock_process_filters, mock_auth
    ):
        """Test paginated fetch when API returns no data."""
        mock_paginator = MagicMock()
        mock_paginator.fetch_all.return_value = iter([])
        mock_paginator_class.return_value = mock_paginator

        job_args = {
            "endpoint": "events",
            "base_filters": {"paging": "true"},
            "load_start_date": "2025-01-01",
            "load_end_date": "2025-01-31",
        }

        api_client = GreenhouseAuditLogAPI(job_args)
        # Manually set params since _process_filters is mocked
        api_client.params = {"paging": "true"}
        results = api_client.get_all_paginated_results()

        self.assertEqual(results, [])


class TestMainFunction(unittest.TestCase):
    """Tests for the main function."""

    def setUp(self):
        """Set up test fixtures."""
        self.job_args = {
            "table_name": "greenhouse_audit_events",
            "endpoint": "events",
            "base_filters": {"paging": "true"},
            "load_start_date": "2025-01-01",
            "load_end_date": "2025-01-31",
            "environment": "forno",
            "dag_name": "greenhouse_audit_log",
            "datalake_bucket": "test-bucket",
            "partition_cols": ["year", "month", "day"],
            "extraction_type": "full",
            "date_column_to_partition": "event_time",
        }

    @patch(
        "dags.people.greenhouse_audit_log.spark_jobs.load_greenhouse_audit_log_raw._run_load_for_window"
    )
    @patch(
        "dags.people.greenhouse_audit_log.spark_jobs.load_greenhouse_audit_log_raw.BaseJobArgumentParser"
    )
    @patch(
        "dags.people.greenhouse_audit_log.spark_jobs.load_greenhouse_audit_log_raw.SparkClient"
    )
    @patch(
        "dags.people.greenhouse_audit_log.spark_jobs.load_greenhouse_audit_log_raw.SparkSession"
    )
    def test_main_success_with_data(
        self,
        mock_spark_session,
        mock_spark_client_class,
        mock_parser,
        mock_run_load,
    ):
        """Test main function successfully loads data when API returns records."""
        mock_parser.parse_args.return_value = self.job_args
        mock_spark_client_class.return_value = MagicMock()
        mock_spark_session.builder.getOrCreate.return_value = MagicMock()

        mock_run_load.return_value = (2, 0)

        main()

        expected_load_start = "2025-01-01T00:00:00Z"
        expected_load_end = "2025-01-31T00:00:00Z"
        mock_run_load.assert_called_once()
        call_args = mock_run_load.call_args[0]
        self.assertEqual(call_args[3], expected_load_start)
        self.assertEqual(call_args[4], expected_load_end)

    @patch(
        "dags.people.greenhouse_audit_log.spark_jobs.load_greenhouse_audit_log_raw.BaseJobArgumentParser"
    )
    @patch(
        "dags.people.greenhouse_audit_log.spark_jobs.load_greenhouse_audit_log_raw.SparkClient"
    )
    @patch(
        "dags.people.greenhouse_audit_log.spark_jobs.load_greenhouse_audit_log_raw.SparkSession"
    )
    @patch(
        "dags.people.greenhouse_audit_log.spark_jobs.load_greenhouse_audit_log_raw.GreenhouseAuditLogAPI"
    )
    @patch(
        "dags.people.greenhouse_audit_log.spark_jobs.load_greenhouse_audit_log_raw.RawLayerLoader"
    )
    def test_main_no_data_returned(
        self,
        mock_raw_loader_class,
        mock_api_class,
        mock_spark_session,
        mock_spark_client_class,
        mock_parser,
    ):
        """Test main function handles empty API response gracefully."""
        # Setup mocks
        mock_parser.parse_args.return_value = self.job_args

        # Mock API response with no data via fetch_pages_with_resume
        mock_api_client = MagicMock()

        def mock_fetch_empty(on_page, on_before_resume=None):
            return 0, 0

        mock_api_client.fetch_pages_with_resume = MagicMock(side_effect=mock_fetch_empty)
        mock_api_class.return_value = mock_api_client

        # Execute
        main()

        # Verify API was called
        mock_api_client.fetch_pages_with_resume.assert_called_once()

        # RawLayerLoader is created but load_to_raw is not called (batch empty)
        mock_raw_loader_class.assert_called_once()

    @patch(
        "dags.people.greenhouse_audit_log.spark_jobs.load_greenhouse_audit_log_raw.BaseJobArgumentParser"
    )
    @patch(
        "dags.people.greenhouse_audit_log.spark_jobs.load_greenhouse_audit_log_raw.SparkClient"
    )
    @patch(
        "dags.people.greenhouse_audit_log.spark_jobs.load_greenhouse_audit_log_raw.SparkSession"
    )
    @patch(
        "dags.people.greenhouse_audit_log.spark_jobs.load_greenhouse_audit_log_raw.GreenhouseAuditLogAPI"
    )
    @patch(
        "dags.people.greenhouse_audit_log.spark_jobs.load_greenhouse_audit_log_raw.json_to_dataframe"
    )
    @patch(
        "dags.people.greenhouse_audit_log.spark_jobs.load_greenhouse_audit_log_raw.insert_partitions"
    )
    @patch(
        "dags.people.greenhouse_audit_log.spark_jobs.load_greenhouse_audit_log_raw.RawLayerLoader"
    )
    def test_main_uses_default_partition_column(
        self,
        mock_raw_loader_class,
        mock_insert_partitions,
        mock_json_to_df,
        mock_api_class,
        mock_spark_session,
        mock_spark_client_class,
        mock_parser,
    ):
        """Test main function uses default partition column when not specified."""
        # Remove date_column_to_partition from job_args
        job_args = self.job_args.copy()
        del job_args["date_column_to_partition"]

        mock_parser.parse_args.return_value = job_args
        mock_spark_client = MagicMock()
        mock_spark_client_class.return_value = mock_spark_client
        mock_spark = MagicMock()
        mock_spark_session.builder.getOrCreate.return_value = mock_spark

        # Mock API response via fetch_pages_with_resume
        mock_api_client = MagicMock()
        api_data = [{"id": "evt_1", "action": "create"}]

        def mock_fetch_default(on_page, on_before_resume=None):
            if api_data:
                on_page(api_data)
            return len(api_data), 0

        mock_api_client.fetch_pages_with_resume = mock_fetch_default
        mock_api_class.return_value = mock_api_client

        # Mock DataFrame operations
        mock_df = MagicMock()
        mock_json_to_df.return_value = mock_df
        mock_df_with_partitions = MagicMock()
        mock_insert_partitions.return_value = mock_df_with_partitions

        # Mock RawLayerLoader
        mock_raw_loader = MagicMock()
        mock_raw_loader_class.return_value = mock_raw_loader

        # Execute
        main()

        # Verify default partition column was used
        mock_insert_partitions.assert_called_once_with(
            mock_df, DEFAULT_PARTITION_COLUMN
        )

    @patch(
        "dags.people.greenhouse_audit_log.spark_jobs.load_greenhouse_audit_log_raw.BaseJobArgumentParser"
    )
    @patch(
        "dags.people.greenhouse_audit_log.spark_jobs.load_greenhouse_audit_log_raw.GreenhouseAuditLogAPI"
    )
    def test_main_handles_exception(self, mock_api_class, mock_parser):
        """Test main function raises exception on error."""
        mock_parser.parse_args.return_value = self.job_args

        # Mock API to raise an exception
        mock_api_class.side_effect = Exception("API connection failed")

        # Execute and verify exception is raised
        with self.assertRaises(Exception) as context:
            main()

        self.assertIn("API connection failed", str(context.exception))

    @patch(
        "dags.people.greenhouse_audit_log.spark_jobs.load_greenhouse_audit_log_raw.BaseJobArgumentParser"
    )
    @patch(
        "dags.people.greenhouse_audit_log.spark_jobs.load_greenhouse_audit_log_raw.SparkClient"
    )
    @patch(
        "dags.people.greenhouse_audit_log.spark_jobs.load_greenhouse_audit_log_raw.SparkSession"
    )
    @patch(
        "dags.people.greenhouse_audit_log.spark_jobs.load_greenhouse_audit_log_raw.GreenhouseAuditLogAPI"
    )
    @patch(
        "dags.people.greenhouse_audit_log.spark_jobs.load_greenhouse_audit_log_raw.RawLayerLoader"
    )
    def test_main_handles_exception_during_fetch(
        self,
        mock_raw_loader_class,
        mock_api_class,
        mock_spark_session,
        mock_spark_client_class,
        mock_parser,
    ):
        """Test main function raises exception if API fetch fails (not init)."""
        # Setup mocks
        mock_parser.parse_args.return_value = self.job_args
        mock_spark_client_class.return_value = MagicMock()
        mock_spark_session.builder.getOrCreate.return_value = MagicMock()

        # Mock API client to fail on fetch_pages_with_resume
        mock_api_client = MagicMock()
        mock_api_client.fetch_pages_with_resume = MagicMock(
            side_effect=Exception("API fetch failed")
        )
        mock_api_class.return_value = mock_api_client  # Init works

        # Execute and verify exception was raised
        with self.assertRaises(Exception) as context:
            main()

        self.assertIn("API fetch failed", str(context.exception))
        # Verify API was called
        mock_api_client.fetch_pages_with_resume.assert_called_once()


if __name__ == "__main__":
    unittest.main()
