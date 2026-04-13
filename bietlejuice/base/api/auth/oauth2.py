import json
import logging
import time
from typing import Dict, Any, Optional

import requests
from dateutil import parser
from requests.auth import AuthBase as RequestsAuthBase

from bietlejuice.base.api.auth.base import AuthBase

LOGGER = logging.getLogger(__name__)


class BasicAuthOAuth2ClientCredentials(AuthBase, RequestsAuthBase):
    """
    Handles the OAuth 2.0 client credentials flow where the token endpoint
    is protected by Basic Authentication using a client ID and client secret.

    This class automatically fetches a new access token when the current one is
    non-existent or expired and attaches it to outgoing requests as a Bearer
    token.
    """

    def __init__(
        self,
        databricks_scope: str,
        secret_key: str,
        token_url: str,
        client_id_field: str = "client_id",
        client_secret_field: str = "client_secret",
        token_payload_extras: Optional[Dict[str, Any]] = None,
        expires_at_field: str = "expires_at",
        expires_in_field: str = "expires_in",
        token_expiration_margin_seconds: int = 60,
        fallback_token_expiration_seconds: int = 3600,
        token_request_format: str = "form_basic_auth",
        access_token_field: str = "access_token",
        http_user_agent: Optional[str] = None,
    ):
        """
        Initializes the OAuth 2.0 client credentials authentication handler.

        Args:
            databricks_scope (str): The Databricks secret scope where credentials
                are stored.
            secret_key (str): The key within the scope to retrieve the client ID
                and secret.
            token_url (str): The URL of the OAuth 2.0 token endpoint.
            client_id_field (str): The key name for the client ID in the
                retrieved secret. Defaults to "client_id".
            client_secret_field (str): The key name for the client secret in the
                retrieved secret. Defaults to "client_secret".
            token_payload_extras (Optional[Dict[str, Any]]): A dictionary of
                extra key-value pairs to include in the token request payload.
            expires_at_field (str): The field name in the token response JSON
                that contains the absolute expiration timestamp.
            expires_in_field (str): The field name in the token response JSON
                that contains the token's lifetime in seconds.
            token_expiration_margin_seconds (int): A buffer in seconds to
                preemptively refresh the token before it expires.
            fallback_token_expiration_seconds (int): The token lifetime in
                seconds to assume if expiration is not provided or fails to parse.
            token_request_format (str): ``form_basic_auth`` (default) sends
                ``application/x-www-form-urlencoded`` body with ``grant_type`` and
                extras, and HTTP Basic Auth with client id/secret. ``json_body``
                sends a JSON object including ``client_id``, ``client_secret``,
                ``grant_type``, and ``token_payload_extras`` (no HTTP Basic Auth).
            access_token_field (str): JSON field name for the bearer token in the
                token response (default ``access_token``; some APIs use camelCase).
            http_user_agent (Optional[str]): If set, sent as ``User-Agent`` on the
                token HTTP request (e.g. when a provider blocks default Python clients).
        """
        super().__init__(databricks_scope, secret_key)
        self.token_url = token_url
        self.client_id_field = client_id_field
        self.client_secret_field = client_secret_field
        self.token_payload_extras = token_payload_extras or {}
        self.expires_at_field = expires_at_field
        self.expires_in_field = expires_in_field
        self.token_expiration_margin_seconds = token_expiration_margin_seconds
        self.fallback_token_expiration_seconds = fallback_token_expiration_seconds
        self.token_request_format = token_request_format
        self.access_token_field = access_token_field
        self.http_user_agent = http_user_agent

        self._access_token: Optional[str] = None
        self._token_expires_at: float = 0.0

    def _is_token_expired(self) -> bool:
        """
        Checks if the current access token has expired or is about to expire
        within a configurable margin.

        Returns:
            bool: True if the token is expired or nearing expiration,
                  False otherwise.
        """
        return time.time() >= (
            self._token_expires_at - self.token_expiration_margin_seconds
        )

    def _fetch_new_token(self):
        """
        Fetches a new access token from the token endpoint using client
        credentials and updates the internal state with the new token and its
        expiration time.

        Raises:
            ValueError: If the client ID, client secret, or access token are
                        not found in their respective sources.
            requests.RequestException: For any network-related errors during
                                       the token fetch process.
        """
        secrets = self._get_secrets_from_dbutils()
        client_id = secrets.get(self.client_id_field)
        client_secret = secrets.get(self.client_secret_field)

        if not client_id or not client_secret:
            raise ValueError(
                f"'{self.client_id_field}' or '{self.client_secret_field}' "
                "not found in the secret."
            )

        common_headers: Dict[str, str] = {"Accept": "application/json"}
        if self.http_user_agent:
            common_headers["User-Agent"] = self.http_user_agent

        try:
            if self.token_request_format == "json_body":
                payload = {
                    "client_id": client_id,
                    "client_secret": client_secret,
                    "grant_type": "client_credentials",
                }
                payload.update(self.token_payload_extras)
                headers = {
                    **common_headers,
                    "Content-Type": "application/json",
                }
                LOGGER.info(
                    "Fetching new OAuth 2.0 token from '%s' using JSON body.",
                    self.token_url,
                )
                response = requests.post(
                    self.token_url,
                    headers=headers,
                    data=json.dumps(payload),
                    timeout=60,
                )
            elif self.token_request_format == "form_basic_auth":
                data = {"grant_type": "client_credentials"}
                data.update(self.token_payload_extras)
                headers = {
                    **common_headers,
                    "Content-Type": "application/x-www-form-urlencoded",
                }
                auth = (client_id, client_secret)
                LOGGER.info(
                    "Fetching new OAuth 2.0 token from '%s' using Basic Auth.",
                    self.token_url,
                )
                response = requests.post(
                    self.token_url,
                    headers=headers,
                    data=data,
                    auth=auth,
                    timeout=60,
                )
            else:
                raise ValueError(
                    f"Unsupported token_request_format: {self.token_request_format!r}. "
                    "Use 'form_basic_auth' or 'json_body'."
                )

            response.raise_for_status()
            response_json = response.json()

            self._access_token = response_json.get(self.access_token_field)
            if not self._access_token:
                raise ValueError(
                    f"'{self.access_token_field}' not found in the token response."
                )

            if self.expires_at_field in response_json:
                expires_at_str = response_json[self.expires_at_field]
                try:
                    # Parse the ISO 8601 date string and convert to a Unix timestamp
                    self._token_expires_at = parser.parse(expires_at_str).timestamp()
                except (ValueError, TypeError):
                    LOGGER.error(
                        f"Could not parse expires_at timestamp: {expires_at_str}"
                    )
                    self._token_expires_at = (
                        time.time() + self.fallback_token_expiration_seconds
                    )
            elif self.expires_in_field in response_json:
                self._token_expires_at = time.time() + int(
                    response_json[self.expires_in_field]
                )
            else:
                LOGGER.warning(
                    f"Neither '{self.expires_at_field}' nor "
                    f"'{self.expires_in_field}' found. Assuming {self.fallback_token_expiration_seconds} seconds expiration."
                )
                self._token_expires_at = (
                    time.time() + self.fallback_token_expiration_seconds
                )

            LOGGER.info(
                "New token obtained. Expires at: "
                f"{time.ctime(self._token_expires_at)}"
            )

        except requests.RequestException as e:
            LOGGER.error(f"HTTP error while fetching token: {e}", exc_info=True)
            raise

    def __call__(self, r: requests.PreparedRequest) -> requests.PreparedRequest:
        """
        Attaches the Authorization header to the request.

        This method is called by the `requests` library before sending a
        request. It ensures a valid access token is present, fetching a new
        one if necessary.

        Args:
            r (requests.PreparedRequest): The request to modify.

        Returns:
            requests.PreparedRequest: The modified request with the
                                      Authorization header.
        """
        if self._access_token is None or self._is_token_expired():
            self._fetch_new_token()
        r.headers["Authorization"] = f"Bearer {self._access_token}"
        return r

    def apply_auth(self, session: requests.Session):
        """
        Applies this authentication handler to a requests.Session object.

        Args:
            session (requests.Session): The session to which this
                                        authentication will be applied.
        """
        session.auth = self
