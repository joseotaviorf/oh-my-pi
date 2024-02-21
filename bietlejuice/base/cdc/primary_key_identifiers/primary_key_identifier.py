from abc import ABC, abstractmethod
from typing import List


class PrimaryKeyIdentifier(ABC):
    @abstractmethod
    def find_primary_keys(schema: str, table_name: str) -> List[str]:
        """Returns a list of primary keys for the specified table"""
