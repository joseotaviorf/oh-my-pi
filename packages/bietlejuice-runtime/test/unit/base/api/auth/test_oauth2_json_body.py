"""Unit tests for OAuth2 client-credentials variants used by API ingestion."""

import json
from unittest.mock import Mock, patch

from bietlejuice.base.api.auth.oauth2 import BasicAuthOAuth2ClientCredentials


@patch("bietlejuice.base.api.auth.oauth2.requests.post")
@patch.object(BasicAuthOAuth2ClientCredentials, "_get_secrets_from_dbutils")
def test_fetch_token_json_body_with_camel_case_access_token(mock_secrets, mock_post):
    """
    Token endpoints that expect a JSON body and return camelCase fields (e.g. Oitchau)
    should obtain the bearer token and parse absolute expiry.
    """
    mock_secrets.return_value = {"client_id": "cid", "client_secret": "csec"}
    mock_response = Mock()
    mock_response.raise_for_status = Mock()
    mock_response.json.return_value = {
        "accessToken": "tok-123",
        "accessTokenExpiresAt": "2026-12-31T23:59:59.000Z",
    }
    mock_post.return_value = mock_response

    auth = BasicAuthOAuth2ClientCredentials(
        databricks_scope="people",
        secret_key="OITCHAU_INTEGRATIONS_API",
        token_url="https://api.example.com/token",
        token_request_format="json_body",
        access_token_field="accessToken",
        expires_at_field="accessTokenExpiresAt",
        token_payload_extras={"response_type": "token"},
        http_user_agent="OitchauIngestion/1.0",
    )
    auth._fetch_new_token()

    assert auth._access_token == "tok-123"
    mock_post.assert_called_once()
    call_kwargs = mock_post.call_args.kwargs
    assert call_kwargs["headers"]["Content-Type"] == "application/json"
    body = json.loads(call_kwargs["data"])
    assert body["client_id"] == "cid"
    assert body["client_secret"] == "csec"
    assert body["grant_type"] == "client_credentials"
    assert body["response_type"] == "token"
    assert call_kwargs["headers"]["User-Agent"] == "OitchauIngestion/1.0"


@patch("bietlejuice.base.api.auth.oauth2.requests.post")
@patch.object(BasicAuthOAuth2ClientCredentials, "_get_secrets_from_dbutils")
def test_fetch_token_form_basic_auth_unchanged(mock_secrets, mock_post):
    """Default form + HTTP Basic token request still returns access_token."""
    mock_secrets.return_value = {"client_id": "cid", "client_secret": "csec"}
    mock_response = Mock()
    mock_response.raise_for_status = Mock()
    mock_response.json.return_value = {
        "access_token": "classic",
        "expires_in": 3600,
    }
    mock_post.return_value = mock_response

    auth = BasicAuthOAuth2ClientCredentials(
        databricks_scope="scope",
        secret_key="KEY",
        token_url="https://api.example.com/oauth/token",
    )
    auth._fetch_new_token()

    assert auth._access_token == "classic"
    mock_post.assert_called_once()
    assert mock_post.call_args.kwargs["auth"] == ("cid", "csec")
    assert (
        mock_post.call_args.kwargs["headers"]["Content-Type"]
        == "application/x-www-form-urlencoded"
    )
    assert "User-Agent" not in mock_post.call_args.kwargs["headers"]
