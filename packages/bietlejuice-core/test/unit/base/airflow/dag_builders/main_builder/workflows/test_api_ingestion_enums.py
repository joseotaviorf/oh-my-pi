"""
Unit tests for API Ingestion workflow enums.

Tests the enum classes used by the API Ingestion workflow.
"""

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.api_ingestion_enums import (
    AuthenticationStrategyEnum,
    HttpMethodEnum,
    PaginationStrategyEnum,
    RateLimitingStrategyEnum,
)


class TestAuthenticationStrategyEnum:
    """Test suite for AuthenticationStrategyEnum."""

    def test_oauth2_client_credentials_value(self):
        """Test that OAUTH2_CLIENT_CREDENTIALS has correct value."""
        assert (
            AuthenticationStrategyEnum.OAUTH2_CLIENT_CREDENTIALS.value
            == "oauth2_client_credentials"
        )

    def test_basic_value(self):
        """Test that BASIC has correct value."""
        assert AuthenticationStrategyEnum.BASIC.value == "basic"

    def test_none_value(self):
        """Test that NONE has correct value."""
        assert AuthenticationStrategyEnum.NONE.value == "none"

    def test_api_key_value(self):
        """Test that API_KEY has correct value."""
        assert AuthenticationStrategyEnum.API_KEY.value == "api_key"

    def test_get_available_enum_values(self):
        """Test that get_available_enum_values returns all enum values."""
        values = AuthenticationStrategyEnum.get_available_enum_values()
        assert "oauth2_client_credentials" in values
        assert "basic" in values
        assert "api_key" in values
        assert "none" in values
        assert len(values) == 4


class TestPaginationStrategyEnum:
    """Test suite for PaginationStrategyEnum."""

    def test_cursor_value(self):
        """Test that CURSOR has correct value."""
        assert PaginationStrategyEnum.CURSOR.value == "cursor"

    def test_offset_limit_value(self):
        """Test that OFFSET_LIMIT has correct value."""
        assert PaginationStrategyEnum.OFFSET_LIMIT.value == "offset_limit"

    def test_none_value(self):
        """Test that NONE has correct value."""
        assert PaginationStrategyEnum.NONE.value == "none"

    def test_page_per_page_value(self):
        """Test that PAGE_PER_PAGE has correct value."""
        assert PaginationStrategyEnum.PAGE_PER_PAGE.value == "page_per_page"

    def test_get_available_enum_values(self):
        """Test that get_available_enum_values returns all enum values."""
        values = PaginationStrategyEnum.get_available_enum_values()
        assert "cursor" in values
        assert "offset_limit" in values
        assert "page_per_page" in values
        assert "none" in values
        assert len(values) == 4


class TestHttpMethodEnum:
    """Test suite for HttpMethodEnum."""

    def test_get_available_enum_values(self):
        """Test that get_available_enum_values returns get and post."""
        assert HttpMethodEnum.get_available_enum_values() == ["get", "post"]


class TestRateLimitingStrategyEnum:
    """Test suite for RateLimitingStrategyEnum."""

    def test_fixed_delay_value(self):
        """Test that FIXED_DELAY has correct value."""
        assert RateLimitingStrategyEnum.FIXED_DELAY.value == "fixed_delay"

    def test_none_value(self):
        """Test that NONE has correct value."""
        assert RateLimitingStrategyEnum.NONE.value == "none"

    def test_get_available_enum_values(self):
        """Test that get_available_enum_values returns all enum values."""
        values = RateLimitingStrategyEnum.get_available_enum_values()
        assert "fixed_delay" in values
        assert "none" in values
        assert len(values) == 2
