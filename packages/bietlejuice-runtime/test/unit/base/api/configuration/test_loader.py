"""
Unit tests for APIConfigurationLoader.

Tests the configuration loader that instantiates API components based on YAML configuration.
"""

import os
from unittest.mock import Mock, patch

import pytest

from bietlejuice.base.api.common.client import BaseAPIClient
from bietlejuice.base.api.configuration import APIConfigurationLoader
from bietlejuice.base.api.pagination.cursor import CursorPaginator
from bietlejuice.base.api.pagination.offset_limit import OffsetLimitPaginator


class TestAPIConfigurationLoaderGetAPIBaseURL:
    """Test suite for get_api_base_url method."""

    def test_get_api_base_url_string(self):
        """Test that string api_base_url is returned as-is."""
        workflow_config = {"api_base_url": "https://api.example.com/"}
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        base_url = loader.get_api_base_url()

        assert base_url == "https://api.example.com/"

    def test_get_api_base_url_dict_with_environment(self):
        """Test that dict api_base_url returns correct environment URL."""
        workflow_config = {
            "api_base_url": {
                "forno": "https://api-forno.example.com/",
                "prod": "https://api-prod.example.com/",
            }
        }
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        with patch.dict(os.environ, {"ENVIRONMENT": "forno"}):
            base_url = loader.get_api_base_url()

            assert base_url == "https://api-forno.example.com/"

    def test_get_api_base_url_dict_defaults_to_forno(self):
        """Test that dict api_base_url defaults to 'forno' if ENVIRONMENT not set."""
        workflow_config = {
            "api_base_url": {
                "forno": "https://api-forno.example.com/",
                "prod": "https://api-prod.example.com/",
            }
        }
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        with patch.dict(os.environ, {}, clear=True):
            base_url = loader.get_api_base_url()

            assert base_url == "https://api-forno.example.com/"

    def test_get_api_base_url_missing_raises_error(self):
        """Test that missing api_base_url raises ValueError."""
        workflow_config = {}
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        with pytest.raises(ValueError, match="'api_base_url' is required"):
            loader.get_api_base_url()

    def test_get_api_base_url_dict_invalid_environment_raises_error(self):
        """Test that invalid environment in dict raises ValueError."""
        workflow_config = {
            "api_base_url": {
                "forno": "https://api-forno.example.com/",
                "prod": "https://api-prod.example.com/",
            }
        }
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        with patch.dict(os.environ, {"ENVIRONMENT": "staging"}):
            with pytest.raises(
                ValueError, match="Base URL not found for environment 'staging'"
            ):
                loader.get_api_base_url()

    def test_get_api_base_url_dict_empty_raises_error(self):
        """Test that empty dict raises ValueError."""
        workflow_config = {"api_base_url": {}}
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        with pytest.raises(ValueError, match="Base URL not found for environment"):
            loader.get_api_base_url()

    def test_get_api_base_url_invalid_type_raises_error(self):
        """Test that invalid type for api_base_url raises ValueError."""
        workflow_config = {"api_base_url": 123}
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        with pytest.raises(
            ValueError, match="'api_base_url' must be either a string or a dictionary"
        ):
            loader.get_api_base_url()


class TestAPIConfigurationLoaderCreateAPIClient:
    """Test suite for create_api_client method."""

    @patch("bietlejuice.base.api.configuration.loader.BasicAuthOAuth2ClientCredentials")
    def test_create_api_client_with_oauth2_authentication(self, mock_auth_class):
        """Test that OAuth2 authentication is applied correctly."""
        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "authentication": {
                "strategy": "oauth2_client_credentials",
                "secret_key": "TEST_SECRET",
                "token_url": "https://api.example.com/token",
            },
        }
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        mock_auth_instance = Mock()
        mock_auth_class.return_value = mock_auth_instance

        client = loader.create_api_client()

        assert isinstance(client, BaseAPIClient)
        assert client.base_url == "https://api.example.com/"
        mock_auth_class.assert_called_once()
        assert mock_auth_class.call_args.kwargs["expires_at_field"] == "expires_at"
        assert mock_auth_class.call_args.kwargs["token_payload_extras"] == {}
        assert (
            mock_auth_class.call_args.kwargs["token_request_format"]
            == "form_basic_auth"
        )
        assert mock_auth_class.call_args.kwargs["access_token_field"] == "access_token"
        assert mock_auth_class.call_args.kwargs["http_user_agent"] is None
        mock_auth_instance.apply_auth.assert_called_once()

    @patch("bietlejuice.base.api.configuration.loader.BasicAuthOAuth2ClientCredentials")
    @patch.dict(os.environ, {"DATABRICKS_SECRET_SCOPE": "quintoandar"})
    def test_oauth2_auth_uses_credentials_scope_from_workflow_config(
        self, mock_auth_class
    ):
        """Workflow `credentials_scope` should override env for secret scope."""
        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "credentials_scope": "people",
            "authentication": {
                "strategy": "oauth2_client_credentials",
                "secret_key": "TEST_SECRET",
                "token_url": "https://api.example.com/token",
            },
        }
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        mock_auth_instance = Mock()
        mock_auth_class.return_value = mock_auth_instance

        loader.create_api_client()

        assert mock_auth_class.call_args.kwargs["databricks_scope"] == "people"
        assert mock_auth_class.call_args.kwargs["http_user_agent"] is None

    def test_create_api_client_without_authentication(self):
        """Test that client is created without authentication when strategy is 'none'."""
        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "authentication": {"strategy": "none"},
        }
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        client = loader.create_api_client()

        assert isinstance(client, BaseAPIClient)
        assert client.base_url == "https://api.example.com/"
        assert "Mozilla/5.0" not in client.session.headers.get("User-Agent", "")

    def test_create_api_client_applies_http_user_agent_from_workflow(self):
        """Optional workflow http_user_agent is set on the session and passed to OAuth2."""
        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "http_user_agent": "CustomIntegration/1.0",
            "authentication": {"strategy": "none"},
        }
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        client = loader.create_api_client()

        assert client.session.headers.get("User-Agent") == "CustomIntegration/1.0"

    def test_create_api_client_applies_workflow_http_headers(self):
        """Workflow http_headers are set on the session."""
        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "http_headers": {"anthropic-version": "2023-06-01"},
            "authentication": {"strategy": "none"},
        }
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        client = loader.create_api_client()

        assert client.session.headers.get("anthropic-version") == "2023-06-01"

    def test_create_api_client_http_headers_table_overlay_merges_and_overrides(self):
        """Table http_headers overlay workflow; table wins on the same key."""
        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "http_headers": {
                "anthropic-version": "2023-06-01",
                "X-Tenant": "workflow",
            },
            "authentication": {"strategy": "none"},
        }
        table_config = {
            "endpoint_path": "groups",
            "http_headers": {
                "anthropic-beta": "ce-user-management-2026-07-13",
                "X-Tenant": "table",
            },
        }
        loader = APIConfigurationLoader(workflow_config, table_config)

        client = loader.create_api_client()

        assert client.session.headers.get("anthropic-version") == "2023-06-01"
        assert (
            client.session.headers.get("anthropic-beta")
            == "ce-user-management-2026-07-13"
        )
        assert client.session.headers.get("X-Tenant") == "table"

    def test_create_api_client_http_headers_absent_table_keeps_workflow(self):
        """Missing table http_headers inherits the workflow map."""
        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "http_headers": {"anthropic-version": "2023-06-01"},
            "authentication": {"strategy": "none"},
        }
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        client = loader.create_api_client()

        assert client.session.headers.get("anthropic-version") == "2023-06-01"

    def test_create_api_client_http_user_agent_wins_over_http_headers(self):
        """http_user_agent remains the User-Agent knob when both are set."""
        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "http_headers": {"User-Agent": "FromHeaders/1.0"},
            "http_user_agent": "FromKnob/1.0",
            "authentication": {"strategy": "none"},
        }
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        client = loader.create_api_client()

        assert client.session.headers.get("User-Agent") == "FromKnob/1.0"

    def test_create_api_client_with_retry_policy(self):
        """Test that retry policy is configured correctly."""
        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "authentication": {"strategy": "none"},
            "api_policies": {
                "error_handling": {
                    "retry_policy": {"retries": 3, "delay": 1, "backoff_factor": 2}
                }
            },
        }
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        client = loader.create_api_client()

        assert isinstance(client, BaseAPIClient)
        assert client.base_url == "https://api.example.com/"

    @patch("bietlejuice.base.api.configuration.loader.APIKeyAuth")
    @patch.dict(os.environ, {"DATABRICKS_SECRET_SCOPE": "quintoandar"})
    def test_create_api_client_with_api_key_authentication(self, mock_api_key_auth):
        """Test that API key authentication is applied correctly."""
        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "authentication": {"strategy": "api_key", "secret_key": "TEST_SECRET"},
        }
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        mock_auth_instance = Mock()
        mock_api_key_auth.return_value = mock_auth_instance

        client = loader.create_api_client()

        assert isinstance(client, BaseAPIClient)
        assert client.base_url == "https://api.example.com/"
        mock_api_key_auth.assert_called_once()
        mock_auth_instance.apply_auth.assert_called_once()

    def test_create_api_client_with_custom_status_forcelist(self):
        """Test that retry_policy with status_forcelist creates client (BaseAPIClient uses default status_forcelist)."""
        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "authentication": {"strategy": "none"},
            "api_policies": {
                "error_handling": {
                    "retry_policy": {
                        "retries": 3,
                        "delay": 1,
                        "backoff_factor": 2,
                        "status_forcelist": [500, 503],
                    }
                }
            },
        }
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        client = loader.create_api_client()

        assert isinstance(client, BaseAPIClient)
        assert client.base_url == "https://api.example.com/"
        adapter = client.session.adapters["https://"]
        assert adapter.max_retries.total == 3

    def test_create_api_client_invalid_authentication_strategy_raises_error(self):
        """Test that invalid authentication strategy raises ValueError."""
        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "authentication": {"strategy": "invalid_strategy"},
        }
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        with pytest.raises(
            ValueError, match="Authentication strategy 'invalid_strategy' not supported"
        ):
            loader.create_api_client()

    def test_create_api_client_empty_authentication_raises_error(self):
        """Test that empty authentication config raises ValueError."""
        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "authentication": {},
        }
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        with pytest.raises(
            ValueError, match="Authentication strategy is required and cannot be empty"
        ):
            loader.create_api_client()

    def test_create_api_client_missing_secret_key_raises_error(self):
        """Test that missing secret_key for OAuth2 raises ValueError."""
        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "authentication": {
                "strategy": "oauth2_client_credentials",
                "token_url": "https://api.example.com/token",
            },
        }
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        with pytest.raises(
            ValueError, match="'secret_key' is required for oauth2_client_credentials"
        ):
            loader._apply_oauth2_authentication(
                Mock(), workflow_config["authentication"]
            )

    def test_create_api_client_missing_token_url_raises_error(self):
        """Test that missing token_url for OAuth2 raises ValueError."""
        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "authentication": {
                "strategy": "oauth2_client_credentials",
                "secret_key": "TEST_SECRET",
            },
        }
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        with pytest.raises(
            ValueError, match="'token_url' is required for oauth2_client_credentials"
        ):
            loader._apply_oauth2_authentication(
                Mock(), workflow_config["authentication"]
            )

    @patch("bietlejuice.base.api.configuration.loader.BasicAuth")
    @patch.dict(os.environ, {"DATABRICKS_SECRET_SCOPE": "quintoandar"})
    def test_create_api_client_with_basic_authentication(self, mock_basic_auth_class):
        """Test that Basic authentication is applied correctly."""
        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "authentication": {
                "strategy": "basic",
                "secret_key": "HR_SYSTEM_API",
                "token_field": "api_token",
            },
        }
        table_config = {"endpoint_path": "workers"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        mock_auth_instance = Mock()
        mock_basic_auth_class.return_value = mock_auth_instance

        client = loader.create_api_client()

        assert isinstance(client, BaseAPIClient)
        assert client.base_url == "https://api.example.com/"
        mock_basic_auth_class.assert_called_once()
        mock_auth_instance.apply_auth.assert_called_once()

    @patch("bietlejuice.base.api.configuration.loader.BasicAuth")
    @patch.dict(os.environ, {"DATABRICKS_SECRET_SCOPE": "quintoandar"})
    def test_create_api_client_with_basic_auth_username_password(
        self, mock_basic_auth_class
    ):
        """Test that Basic authentication with username/password works."""
        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "authentication": {
                "strategy": "basic",
                "secret_key": "TEST_SECRET",
                "username_field": "username",
                "password_field": "password",
            },
        }
        table_config = {"endpoint_path": "workers"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        mock_auth_instance = Mock()
        mock_basic_auth_class.return_value = mock_auth_instance

        client = loader.create_api_client()

        assert isinstance(client, BaseAPIClient)
        mock_basic_auth_class.assert_called_once()
        call_kwargs = mock_basic_auth_class.call_args[1]
        assert call_kwargs["username_field"] == "username"
        assert call_kwargs["password_field"] == "password"

    def test_create_api_client_missing_secret_key_basic_auth_raises_error(self):
        """Test that missing secret_key for Basic Auth raises ValueError."""
        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "authentication": {"strategy": "basic"},
        }
        table_config = {"endpoint_path": "workers"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        with pytest.raises(
            ValueError, match="'secret_key' is required for basic authentication"
        ):
            loader._apply_basic_authentication(
                Mock(), workflow_config["authentication"]
            )


class TestAPIConfigurationLoaderCreatePaginator:
    """Test suite for create_paginator method."""

    def test_create_paginator_cursor_strategy(self):
        """Test that cursor pagination creates CursorPaginator."""
        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "api_policies": {
                "pagination": {
                    "strategy": "cursor",
                    "cursor_param": "cursor",
                    "page_size": 100,
                }
            },
        }
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)
        client = Mock(spec=BaseAPIClient)

        paginator = loader.create_paginator(client, "events", {})

        assert isinstance(paginator, CursorPaginator)
        assert paginator.cursor_location == "header"
        assert paginator.context_location == "header"
        assert paginator.page_size_location == "header"

    def test_create_paginator_cursor_location_param_puts_cursor_in_query_params(self):
        """YAML cursor_location param sends the next cursor as a query param."""
        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "api_policies": {
                "pagination": {
                    "strategy": "cursor",
                    "cursor_location": "param",
                    "cursor_param": "page",
                    "cursor_response_path": "next_page",
                }
            },
        }
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)
        client = Mock(spec=BaseAPIClient)
        first_page = Mock()
        first_page.json.return_value = {
            "results": [{"id": 1}],
            "next_page": "cursor-2",
        }
        last_page = Mock()
        last_page.json.return_value = {
            "results": [{"id": 2}],
            "next_page": None,
        }
        client.get.side_effect = [first_page, last_page]

        paginator = loader.create_paginator(client, "events", {})
        list(paginator.fetch_all())

        assert paginator.cursor_location == "param"
        assert paginator.cursor_param == "page"
        assert paginator.cursor_response_path == "next_page"
        second_call_kwargs = client.get.call_args_list[1].kwargs
        assert second_call_kwargs["params"]["page"] == "cursor-2"
        assert "page" not in (second_call_kwargs.get("headers") or {})

    def test_create_paginator_none_strategy(self):
        """Test that 'none' pagination strategy returns None."""
        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "api_policies": {"pagination": {"strategy": "none"}},
        }
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)
        client = Mock(spec=BaseAPIClient)

        paginator = loader.create_paginator(client, "events", {})

        assert paginator is None

    def test_create_paginator_no_config_returns_none(self):
        """Test that missing pagination config returns None."""
        workflow_config = {"api_base_url": "https://api.example.com/"}
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)
        client = Mock(spec=BaseAPIClient)

        paginator = loader.create_paginator(client, "events", {})

        assert paginator is None

    def test_create_paginator_table_level_overrides_workflow_level(self):
        """Test that table-level pagination config overrides workflow-level."""
        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "api_policies": {"pagination": {"strategy": "none"}},
        }
        table_config = {
            "endpoint_path": "events",
            "pagination": {
                "strategy": "cursor",
                "cursor_param": "cursor",
                "page_size": 50,
            },
        }
        loader = APIConfigurationLoader(workflow_config, table_config)
        client = Mock(spec=BaseAPIClient)

        paginator = loader.create_paginator(client, "events", {})

        assert isinstance(paginator, CursorPaginator)
        assert paginator.page_size == 50

    def test_create_paginator_cursor_strategy_with_custom_results_field(self):
        """Test that cursor pagination can use custom results_response_path."""
        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "api_policies": {
                "pagination": {
                    "strategy": "cursor",
                    "cursor_param": "cursor",
                    "page_size": 100,
                    "results_response_path": "data",
                }
            },
        }
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)
        client = Mock(spec=BaseAPIClient)

        paginator = loader.create_paginator(client, "events", {})

        assert isinstance(paginator, CursorPaginator)
        test_response = {"data": [{"id": 1}, {"id": 2}]}
        results = paginator.extract_results(test_response)
        assert results == [{"id": 1}, {"id": 2}]

    def test_create_paginator_cursor_strategy_without_results_field_uses_default(self):
        """Test that cursor pagination uses default extract_results when results_response_path is not specified."""
        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "api_policies": {
                "pagination": {
                    "strategy": "cursor",
                    "cursor_param": "cursor",
                    "page_size": 100,
                }
            },
        }
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)
        client = Mock(spec=BaseAPIClient)

        paginator = loader.create_paginator(client, "events", {})

        assert isinstance(paginator, CursorPaginator)
        test_response = {"items": [{"id": 1}, {"id": 2}]}
        results = paginator.extract_results(test_response)
        assert results == [{"id": 1}, {"id": 2}]

    def test_create_paginator_offset_limit_strategy(self):
        """Test that offset_limit pagination creates OffsetLimitPaginator."""
        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "api_policies": {
                "pagination": {
                    "strategy": "offset_limit",
                    "limit_param": "limit",
                    "offset_param": "offset",
                    "page_size": 100,
                }
            },
        }
        table_config = {"endpoint_path": "workers"}
        loader = APIConfigurationLoader(workflow_config, table_config)
        client = Mock(spec=BaseAPIClient)

        paginator = loader.create_paginator(client, "workers", {})

        assert isinstance(paginator, OffsetLimitPaginator)
        assert paginator.limit_param == "limit"
        assert paginator.offset_param == "offset"
        assert paginator.page_size == 100

    def test_create_paginator_offset_limit_table_level_override(self):
        """Test that table-level offset_limit config overrides workflow-level."""
        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "api_policies": {
                "pagination": {
                    "strategy": "offset_limit",
                    "limit_param": "limit",
                    "offset_param": "offset",
                    "page_size": 100,
                }
            },
        }
        table_config = {
            "endpoint_path": "workers",
            "pagination": {
                "strategy": "offset_limit",
                "limit_param": "count",
                "offset_param": "start",
                "page_size": 50,
            },
        }
        loader = APIConfigurationLoader(workflow_config, table_config)
        client = Mock(spec=BaseAPIClient)

        paginator = loader.create_paginator(client, "workers", {})

        assert isinstance(paginator, OffsetLimitPaginator)
        assert paginator.limit_param == "count"
        assert paginator.offset_param == "start"
        assert paginator.page_size == 50

    def test_create_paginator_page_per_page_strategy(self):
        """Test that page_per_page pagination creates PagePerPagePaginator."""
        from bietlejuice.base.api.pagination.page_per_page import PagePerPagePaginator

        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "api_policies": {
                "pagination": {
                    "strategy": "page_per_page",
                    "page_param": "page",
                    "per_page_param": "per_page",
                    "page_size": 50,
                }
            },
        }
        table_config = {"endpoint_path": "requests"}
        loader = APIConfigurationLoader(workflow_config, table_config)
        client = Mock(spec=BaseAPIClient)

        paginator = loader.create_paginator(client, "requests", {"from": "2025-01-01"})

        assert isinstance(paginator, PagePerPagePaginator)
        assert paginator.page_param == "page"
        assert paginator.per_page_param == "per_page"
        assert paginator.page_size == 50

    def test_create_paginator_page_per_page_post_passes_body_and_response_options(
        self,
    ):
        """POST tables pass method, body, total_pages_path and envelope_fields."""
        # Arrange
        workflow_config = {"api_base_url": "https://api.cursor.com"}
        table_config = {
            "endpoint_path": "teams/spend",
            "http_method": "post",
            "api_policies": {
                "pagination": {
                    "strategy": "page_per_page",
                    "per_page_param": "pageSize",
                    "page_size": 100,
                    "results_response_path": "teamMemberSpend",
                    "total_pages_path": "totalPages",
                    "envelope_fields": ["subscriptionCycleStart"],
                }
            },
        }
        loader = APIConfigurationLoader(workflow_config, table_config)

        # Act
        paginator = loader.create_paginator(
            Mock(spec=BaseAPIClient), "teams/spend", {}, json_body={"foo": 1}
        )

        # Assert
        assert paginator.http_method == "post"
        assert paginator.json_body == {"foo": 1}
        assert paginator.total_pages_path == "totalPages"
        assert paginator.envelope_fields == ["subscriptionCycleStart"]

    def test_create_paginator_post_with_cursor_strategy_raises_error(self):
        """POST bodies are only wired into page_per_page pagination."""
        workflow_config = {"api_base_url": "https://api.example.com/"}
        table_config = {
            "endpoint_path": "events",
            "http_method": "post",
            "api_policies": {"pagination": {"strategy": "cursor"}},
        }
        loader = APIConfigurationLoader(workflow_config, table_config)

        with pytest.raises(ValueError, match="http_method 'post' is not supported"):
            loader.create_paginator(Mock(spec=BaseAPIClient), "events", {})

    def test_create_paginator_invalid_strategy_raises_error(self):
        """Test that invalid pagination strategy raises ValueError."""
        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "api_policies": {"pagination": {"strategy": "invalid_strategy"}},
        }
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)
        client = Mock(spec=BaseAPIClient)

        with pytest.raises(
            ValueError, match="Pagination strategy 'invalid_strategy' not supported"
        ):
            loader.create_paginator(client, "events", {})

    def test_create_paginator_empty_config_raises_error(self):
        """Test that empty pagination config raises ValueError."""
        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "api_policies": {"pagination": {}},
        }
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)
        client = Mock(spec=BaseAPIClient)

        with pytest.raises(
            ValueError, match="Pagination strategy is required and cannot be empty"
        ):
            loader.create_paginator(client, "events", {})


class TestAPIConfigurationLoaderGetEndpointPath:
    """Test suite for get_endpoint_path method."""

    def test_get_endpoint_path(self):
        """Test that endpoint_path is returned correctly."""
        workflow_config = {"api_base_url": "https://api.example.com/"}
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        endpoint_path = loader.get_endpoint_path()

        assert endpoint_path == "events"

    def test_get_endpoint_path_missing_raises_error(self):
        """Test that missing endpoint_path raises ValueError."""
        workflow_config = {"api_base_url": "https://api.example.com/"}
        table_config = {}
        loader = APIConfigurationLoader(workflow_config, table_config)

        with pytest.raises(ValueError, match="'endpoint_path' is required"):
            loader.get_endpoint_path()


class TestAPIConfigurationLoaderGetInitialParams:
    """Test suite for get_initial_params method."""

    def test_get_initial_params_with_date_placeholders(self):
        """Test that date placeholders are replaced with formatted dates."""
        workflow_config = {"api_base_url": "https://api.example.com/"}
        table_config = {
            "endpoint_path": "events",
            "params": {"after_time": "load_start_date", "before_time": "load_end_date"},
        }
        loader = APIConfigurationLoader(workflow_config, table_config)

        params = loader.get_initial_params("2025-01-01", "2025-01-31")

        assert "after_time" in params
        assert "before_time" in params
        assert params["after_time"] == "2025-01-01T00:00:00.000Z"
        assert params["before_time"] == "2025-01-31T23:59:59.999Z"
        # paging parameter is no longer added automatically - must be explicitly configured
        assert "paging" not in params

    def test_get_initial_params_without_table_params_uses_defaults(self):
        """Test that default params are added when table_params is empty."""
        workflow_config = {"api_base_url": "https://api.example.com/"}
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        params = loader.get_initial_params("2025-01-01", "2025-01-31")

        assert params["after_time"] == "2025-01-01T00:00:00.000Z"
        assert params["before_time"] == "2025-01-31T23:59:59.999Z"
        # paging parameter is no longer added automatically - must be explicitly configured
        assert "paging" not in params

    def test_get_initial_params_explicit_empty_params_skips_date_defaults(self):
        """Explicit ``params: {}`` must not inject after_time/before_time (APIs without date filters)."""
        workflow_config = {"api_base_url": "https://api.example.com/"}
        table_config = {"endpoint_path": "employees", "params": {}}
        loader = APIConfigurationLoader(workflow_config, table_config)

        params = loader.get_initial_params("2025-01-01", "2025-01-31")

        assert params == {}

    def test_get_initial_params_with_custom_date_format(self):
        """Test that custom date_format is applied correctly."""
        workflow_config = {"api_base_url": "https://api.example.com/"}
        table_config = {
            "endpoint_path": "events",
            "date_format": "%Y-%m-%dT%H:%M:%S",
            "params": {"after_time": "load_start_date"},
        }
        loader = APIConfigurationLoader(workflow_config, table_config)

        params = loader.get_initial_params("2025-01-01", "2025-01-31")

        assert params["after_time"] == "2025-01-01T00:00:00"

    def test_get_initial_params_preserves_other_params(self):
        """Test that non-date params are preserved."""
        workflow_config = {"api_base_url": "https://api.example.com/"}
        table_config = {
            "endpoint_path": "events",
            "params": {
                "after_time": "load_start_date",
                "filter": "active",
                "sort": "date",
            },
        }
        loader = APIConfigurationLoader(workflow_config, table_config)

        params = loader.get_initial_params("2025-01-01", "2025-01-31")

        assert params["filter"] == "active"
        assert params["sort"] == "date"
        assert params["after_time"] == "2025-01-01T00:00:00.000Z"

    def test_get_initial_params_empty_date_format_raises_error(self):
        """Test that empty string date_format raises ValueError."""
        workflow_config = {"api_base_url": "https://api.example.com/"}
        table_config = {"endpoint_path": "events", "date_format": ""}
        loader = APIConfigurationLoader(workflow_config, table_config)

        with pytest.raises(ValueError, match="date_format cannot be an empty string"):
            loader.get_initial_params("2025-01-01", "2025-01-31")

    def test_get_initial_params_with_epoch_millis_date_format(self):
        """epoch_millis resolves to inclusive UTC day bounds as integers."""
        workflow_config = {"api_base_url": "https://api.example.com/"}
        table_config = {
            "endpoint_path": "events",
            "date_format": "epoch_millis",
            "params": {"from": "load_start_date", "to": "load_end_date"},
        }
        loader = APIConfigurationLoader(workflow_config, table_config)

        params = loader.get_initial_params("2026-09-21", "2026-09-21")

        assert params == {"from": 1789948800000, "to": 1790035199999}


class TestAPIConfigurationLoaderGetHttpMethod:
    """Test suite for get_http_method method."""

    @pytest.mark.parametrize(
        "table_config, expected",
        [
            ({}, "get"),
            ({"http_method": "post"}, "post"),
            ({"http_method": "POST"}, "post"),
        ],
    )
    def test_get_http_method(self, table_config, expected):
        loader = APIConfigurationLoader({}, table_config)

        assert loader.get_http_method() == expected

    def test_get_http_method_invalid_raises_error(self):
        loader = APIConfigurationLoader({}, {"http_method": "put"})

        with pytest.raises(ValueError, match="http_method 'put' not supported"):
            loader.get_http_method()


class TestAPIConfigurationLoaderGetRequestBody:
    """Test suite for get_request_body method."""

    def test_get_request_body_not_configured_returns_none(self):
        loader = APIConfigurationLoader({}, {"endpoint_path": "events"})

        assert loader.get_request_body("2026-09-21", "2026-09-21") is None

    def test_get_request_body_resolves_date_placeholders(self):
        # Arrange
        table_config = {
            "endpoint_path": "teams/daily-usage-data",
            "http_method": "post",
            "date_format": "epoch_millis",
            "body": {
                "startDate": "load_start_date",
                "endDate": "load_end_date",
                "team": "platform",
            },
        }
        loader = APIConfigurationLoader({}, table_config)

        # Act
        body = loader.get_request_body("2026-09-21", "2026-09-21")

        # Assert
        assert body == {
            "startDate": 1789948800000,
            "endDate": 1790035199999,
            "team": "platform",
        }

    def test_get_request_body_non_mapping_raises_error(self):
        loader = APIConfigurationLoader({}, {"body": ["startDate"]})

        with pytest.raises(ValueError, match="'body' must be a mapping"):
            loader.get_request_body("2026-09-21", "2026-09-21")


class TestAPIConfigurationLoaderGetDateColumnForPartitioning:
    """Test suite for get_date_column_for_partitioning method."""

    def test_get_date_column_for_partitioning(self):
        """Test that date_filter_column is returned when configured."""
        workflow_config = {"api_base_url": "https://api.example.com/"}
        table_config = {"endpoint_path": "events", "date_filter_column": "created_at"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        date_column = loader.get_date_column_for_partitioning()

        assert date_column == "created_at"

    def test_get_date_column_for_partitioning_not_configured(self):
        """Test that None is returned when date_column is not configured."""
        workflow_config = {"api_base_url": "https://api.example.com/"}
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        date_column = loader.get_date_column_for_partitioning()

        assert date_column is None


class TestAPIConfigurationLoaderGetPayloadColumnName:
    """Test suite for get_payload_column_name method."""

    def test_get_payload_column_name_from_workflow_config(self):
        """Test that payload_column_name from workflow_config is returned."""
        workflow_config = {"payload_column_name": "raw_payload"}
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        payload_column = loader.get_payload_column_name()

        assert payload_column == "raw_payload"

    def test_get_payload_column_name_from_table_config(self):
        """Test that payload_column_name from table_config takes precedence."""
        workflow_config = {"payload_column_name": "workflow_payload"}
        table_config = {
            "endpoint_path": "events",
            "payload_column_name": "table_payload",
        }
        loader = APIConfigurationLoader(workflow_config, table_config)

        payload_column = loader.get_payload_column_name()

        assert payload_column == "table_payload"

    def test_get_payload_column_name_defaults_to_payload(self):
        """Test that 'payload' is returned when not configured."""
        workflow_config = {}
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        payload_column = loader.get_payload_column_name()

        assert payload_column == "payload"

    def test_get_payload_column_name_table_overrides_workflow(self):
        """Test that table-level payload_column_name overrides workflow-level."""
        workflow_config = {"payload_column_name": "workflow_payload"}
        table_config = {
            "endpoint_path": "events",
            "payload_column_name": "table_payload",
        }
        loader = APIConfigurationLoader(workflow_config, table_config)

        payload_column = loader.get_payload_column_name()

        assert payload_column == "table_payload"


class TestAPIConfigurationLoaderAlertChannel:
    """Test suite for alert_channel configuration in create_api_client method."""

    def test_create_api_client_with_alert_channel(self):
        """Test that client is created when alert_channel is configured (BaseAPIClient does not support it yet)."""
        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "alert_channel": "PEOPLE_ALERTS",
            "authentication": {"strategy": "none"},
        }
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        client = loader.create_api_client()

        assert isinstance(client, BaseAPIClient)
        assert client.base_url == "https://api.example.com/"

    def test_create_api_client_without_alert_channel(self):
        """Test that client is created when alert_channel is not configured."""
        workflow_config = {
            "api_base_url": "https://api.example.com/",
            "authentication": {"strategy": "none"},
        }
        table_config = {"endpoint_path": "events"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        client = loader.create_api_client()

        assert isinstance(client, BaseAPIClient)
        assert client.base_url == "https://api.example.com/"


class TestAPIConfigurationLoaderGetIdExpansionConfig:
    """Test suite for get_id_expansion_config method."""

    def test_returns_none_when_not_configured(self):
        """Test that None is returned when id_expansion is absent from table_config."""
        workflow_config = {"api_base_url": "https://api.example.com/"}
        table_config = {"endpoint_path": "employees/hoursbank/totals"}
        loader = APIConfigurationLoader(workflow_config, table_config)

        assert loader.get_id_expansion_config() is None

    def test_returns_config_when_present(self):
        """Test that the full id_expansion dict is returned when configured."""
        workflow_config = {"api_base_url": "https://api.example.com/"}
        table_config = {
            "endpoint_path": "employees/hoursbank/totals",
            "id_expansion": {
                "source_table": "employees",
                "id_field": "uuid",
                "param_name": "employeeUuid",
            },
        }
        loader = APIConfigurationLoader(workflow_config, table_config)

        config = loader.get_id_expansion_config()

        assert config == {
            "source_table": "employees",
            "id_field": "uuid",
            "param_name": "employeeUuid",
        }

    def test_returns_none_when_explicitly_set_to_none(self):
        """Test that None is returned when id_expansion is explicitly set to None."""
        workflow_config = {"api_base_url": "https://api.example.com/"}
        table_config = {
            "endpoint_path": "employees/hoursbank/totals",
            "id_expansion": None,
        }
        loader = APIConfigurationLoader(workflow_config, table_config)

        assert loader.get_id_expansion_config() is None

    def test_config_with_path_param(self):
        """Test that id_expansion with path_param (URL injection) is returned correctly."""
        workflow_config = {"api_base_url": "https://api.example.com/"}
        table_config = {
            "endpoint_path": "holidays-groups/holidays/employees/{employeeUuid}",
            "id_expansion": {
                "source_table": "employees",
                "id_field": "uuid",
                "path_param": "employeeUuid",
            },
        }
        loader = APIConfigurationLoader(workflow_config, table_config)

        config = loader.get_id_expansion_config()

        assert config["path_param"] == "employeeUuid"
        assert "param_name" not in config
