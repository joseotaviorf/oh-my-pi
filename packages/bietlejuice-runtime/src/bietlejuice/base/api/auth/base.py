import json
import logging
from abc import ABC, abstractmethod
from typing import Any, Dict

import requests

from bietlejuice.base.spark.base_spark import BaseDBUtils

LOGGER = logging.getLogger(__name__)


class AuthBase(ABC):
    """
    Abstract base class for handling different API authentication strategies.
    """

    def __init__(self, databricks_scope: str, secret_key: str):
        self.databricks_scope = databricks_scope
        self.secret_key = secret_key

    def _get_raw_secret(self) -> str:
        """Retrieves the unparsed secret value from the active secret backend."""
        try:
            base_dbutils = BaseDBUtils()
            dbutils = base_dbutils.get_dbutils()
            return dbutils.secrets.get(scope=self.databricks_scope, key=self.secret_key)
        except Exception as e:
            LOGGER.error(
                f"Failed to retrieve secret '{self.secret_key}' from scope "
                f"'{self.databricks_scope}': {e}",
                exc_info=True,
            )
            raise

    def _get_secrets_from_dbutils(self) -> Dict[str, Any]:
        """Retrieves and parses a secret from Databricks Secrets."""
        try:
            secret = json.loads(self._get_raw_secret())
            if not isinstance(secret, dict):
                raise ValueError("Secret must contain a JSON object")
            return secret
        except Exception as e:
            LOGGER.error(
                f"Failed to retrieve secret '{self.secret_key}' from scope '{self.databricks_scope}': {e}",
                exc_info=True,
            )
            raise

    @abstractmethod
    def apply_auth(self, session: requests.Session):
        """
        Applies authentication headers or configuration to the requests session.
        """
        pass
