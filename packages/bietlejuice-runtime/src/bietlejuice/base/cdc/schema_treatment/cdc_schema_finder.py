from abc import ABC, abstractmethod


class CdcSchemaFinder(ABC):
    @abstractmethod
    def find_latest_table_definition(self, table_name: str) -> dict:
        """
        Returns a dictionary with the latest schema definition of a table.
        The structure of the dictionary is the following
        {
            "primaryKeyColumnNames": ["column1", "column2", ...],
            "columns": [
                {
                    "name": "column1",
                    "typeName": "VARCHAR",
                    "length": 255,
                    "scale": None,
                },
                {
                    "name": "column2",
                    "typeName": "NUMERIC",
                    "length": 11,
                    "scale": 2,
                },
                ...
            ]
        }
        """

        pass
