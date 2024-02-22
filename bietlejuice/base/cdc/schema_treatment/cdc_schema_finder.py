from abc import ABC, abstractmethod


class CdcSchemaFinder(ABC):
    @abstractmethod
    def find_latest_table_definition(self, schema: str, table_name: str) -> dict:
        """
        Returns a dictionary with the latest schema definition of a table.
        The structure of the dictionary depends on the database type.
        """

        pass
