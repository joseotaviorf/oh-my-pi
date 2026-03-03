import logging
from typing import Optional
from urllib.parse import urlparse, urlunparse, parse_qsl, urlencode

import requests
from requests.auth import AuthBase as RequestsAuthBase

from bietlejuice.base.api.auth.base import AuthBase

LOGGER = logging.getLogger(__name__)


class APIKeyAuth(AuthBase, RequestsAuthBase):
    """
    Authentication handler that adds an API key to each HTTP request.

    The API key is loaded from Databricks Secrets (as a JSON field) and can be applied
    either as an HTTP header or as a query parameter, depending on API requirements.

    Supported locations:
    - `header`: Sets the API key as an HTTP header (default header name: `x-api-key`)
    - `query_param`: Appends the API key as a query parameter (default param name: `token`)

    Args:
        databricks_scope: Databricks secret scope name
        secret_key: Secret key name in the Databricks scope
        api_key_field: Field name in the secret JSON containing the API key (default: "api_key")
        location: Where to apply the API key - "header" or "query_param" (default: "header")
        header_name: HTTP header name when using header location (default: "x-api-key")
        query_param_name: Query parameter name when using query_param location (default: "token")

    Raises:
        ValueError: If the API key field is not found in the secret or if an unsupported
                    location is specified
    """

    def __init__(
        self,
        databricks_scope: str,
        secret_key: str,
        api_key_field: str = "api_key",
        location: str = "header",
        header_name: str = "x-api-key",
        query_param_name: str = "token",
    ):
        super().__init__(databricks_scope, secret_key)
        self.api_key_field = api_key_field
        self.location = location
        self.header_name = header_name
        self.query_param_name = query_param_name

        self._api_key: Optional[str] = None
        self._load_api_key()

    def _load_api_key(self) -> None:
        """
        Loads the API key from Databricks Secrets.

        Raises:
            ValueError: If the API key field is not found in the secret
        """
        secrets = self._get_secrets_from_dbutils()
        api_key = secrets.get(self.api_key_field)
        if not api_key:
            raise ValueError(
                f"API key field '{self.api_key_field}' not found in secret '{self.secret_key}'"
            )
        self._api_key = api_key

    def __call__(self, r: requests.PreparedRequest) -> requests.PreparedRequest:
        """
        Modifies the prepared request to include the API key.

        Applies the API key either as an HTTP header or query parameter based on
        the configured location. If the API key hasn't been loaded yet, it will
        be loaded automatically.

        Args:
            r: The prepared HTTP request to modify

        Returns:
            requests.PreparedRequest: The modified request with API key applied

        Raises:
            ValueError: If an unsupported location is configured
        """
        if not self._api_key:
            self._load_api_key()

        if self.location == "header":
            r.headers[self.header_name] = self._api_key
            return r

        if self.location == "query_param":
            parsed = urlparse(r.url)
            query = dict(parse_qsl(parsed.query, keep_blank_values=True))
            query[self.query_param_name] = self._api_key
            new_query = urlencode(query)
            r.url = urlunparse(parsed._replace(query=new_query))
            return r

        raise ValueError(
            f"API key location '{self.location}' not supported. Supported: header, query_param"
        )

    def apply_auth(self, session: requests.Session):
        session.auth = self
        LOGGER.info("API key authentication configured")
