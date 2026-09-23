import base64
import json
import logging
from typing import Optional

import requests
from requests.auth import AuthBase as RequestsAuthBase

from bietlejuice.base.api.auth.base import AuthBase

LOGGER = logging.getLogger(__name__)


class BasicAuth(AuthBase, RequestsAuthBase):
    """
    Handles Basic Authentication using an API token stored in Databricks Secrets.

    This class fetches the API token from Databricks Secrets and attaches it to
    outgoing requests as a Basic Authentication header (Authorization: Basic <token>).

    The token can be stored in the secret as:
    - A single field (e.g., "api_token") that is already Base64-encoded
    - A raw token string, which is encoded as "<token>:"
    - Or username:password format that will be encoded
    """

    def __init__(
        self,
        databricks_scope: str,
        secret_key: str,
        token_field: str = "api_token",
        username_field: Optional[str] = None,
        password_field: Optional[str] = None,
    ):
        """
        Initializes the Basic Authentication handler.

        Args:
            databricks_scope (str): The Databricks secret scope where credentials
                are stored.
            secret_key (str): The key within the scope to retrieve the token/credentials.
            token_field (str): The key name for the API token in the retrieved secret.
                If the token is already Base64-encoded, it should be used directly.
                Defaults to "api_token".
            username_field (Optional[str]): If provided, will encode username:password
                instead of using a pre-encoded token. The username field name in the secret.
            password_field (Optional[str]): If provided, will encode username:password
                instead of using a pre-encoded token. The password field name in the secret.
        """
        super().__init__(databricks_scope, secret_key)
        self.token_field = token_field
        self.username_field = username_field
        self.password_field = password_field
        self._encoded_token = None
        self._load_token()

    def _load_token(self):
        """Loads and encodes the token from Databricks Secrets."""
        try:
            raw_secret = self._get_raw_secret()
            try:
                secrets = json.loads(raw_secret)
            except json.JSONDecodeError:
                secrets = raw_secret

            if (
                isinstance(secrets, dict)
                and self.username_field
                and self.password_field
            ):
                username = secrets.get(self.username_field)
                password = secrets.get(self.password_field)

                if not username or not password:
                    raise ValueError(
                        f"Both '{self.username_field}' and '{self.password_field}' "
                        f"must be present in secret '{self.secret_key}'"
                    )

                auth_string = f"{username}:{password}"
                self._encoded_token = base64.b64encode(
                    auth_string.encode("utf-8")
                ).decode("utf-8")
                LOGGER.info("Basic Auth token created from username:password")
            elif isinstance(secrets, dict):
                # Use pre-encoded token
                token = secrets.get(self.token_field)
                if not token:
                    raise ValueError(
                        f"Token field '{self.token_field}' not found in "
                        f"secret '{self.secret_key}'"
                    )
                self._encoded_token = token
                LOGGER.info("Basic Auth token loaded from secret")
            elif isinstance(secrets, str) and not (
                self.username_field or self.password_field
            ):
                raw_token = secrets.strip()
                if not raw_token:
                    raise ValueError(
                        f"Secret '{self.secret_key}' contains an empty token"
                    )
                self._encoded_token = base64.b64encode(f"{raw_token}:".encode()).decode(
                    "utf-8"
                )
                LOGGER.info("Basic Auth token created from raw secret")
            else:
                raise ValueError(
                    f"Secret '{self.secret_key}' must contain a JSON object or raw token"
                )

        except Exception as e:
            LOGGER.error(
                f"Failed to load Basic Auth token from secret '{self.secret_key}': {e}",
                exc_info=True,
            )
            raise

    def __call__(self, r: requests.PreparedRequest) -> requests.PreparedRequest:
        """
        Attaches the Authorization header to the request.

        This method is called by the `requests` library before sending a request.
        It adds the Basic Authentication header to the request.

        Args:
            r (requests.PreparedRequest): The request to modify.

        Returns:
            requests.PreparedRequest: The modified request with the
                                      Authorization header.
        """
        r.headers["Authorization"] = f"Basic {self._encoded_token}"
        return r

    def apply_auth(self, session: requests.Session):
        """
        Applies this authentication handler to a requests.Session object.

        Args:
            session (requests.Session): The session to which this
                                        authentication will be applied.
        """
        session.auth = self
        LOGGER.info("Basic Auth authentication configured")
