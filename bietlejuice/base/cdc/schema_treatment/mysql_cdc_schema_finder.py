import re
from bietlejuice.base.cdc.schema_treatment.cdc_schema_finder import CdcSchemaFinder
from bietlejuice.consumers.db_consumers.mysql_consumer import MySqlConsumer


class MySqlCdcSchemaFinder(CdcSchemaFinder):
    def __init__(self, mysql_consumer: MySqlConsumer) -> None:
        """
        This class identifies the schema of the table based by querying the database.
        """

        self.mysql_consumer = mysql_consumer

    def _get_column_type_length(self, typeName):
        """
        Returns the length of a data type.
        e.g.:
            VARCHAR(255) -> 255
            TINYINT(1) -> 1
            TINYINT -> None
            DECIMAL(14,4) -> 14
        """
        pattern = r"\b\w+\((\d+)(?:,\d+)?\)"
        match = re.search(pattern, typeName)
        if match:
            return int(match.group(1))
        else:
            return None

    def _get_column_type_scale(self, typeName):
        """
        Returns the scale of a data type.
        e.g.:
            VARCHAR(255) -> None
            TINYINT(1) -> None
            TINYINT -> None
            DECIMAL(14,4) -> 4
        """
        pattern = r"\b\w+\(\d+,\s*(\d+)\)"
        match = re.search(pattern, typeName)
        if match:
            return int(match.group(1))
        else:
            return None

    def format_columns_dict(self, columns_metadata_list: list) -> list:
        """
        Apply some standards in columns_dict:
            1. Upper case one typeName
            2. Extract length
            3. Extract scales
            4. Remove length and scale from the typeName
        e.g.:
        columns_metadata_list = [{
            "name": "column_name",
            "typeName": "decimal(14,4)"
        }, ...]
        will turn into
        columns_metadata_list = [{
            "name": "column_name",
            "typeName": "DECIMAL",
            "length": 14,
            "scale": 4
        }, ...]
        """
        for column_metadata in columns_metadata_list:
            length = self._get_column_type_length(column_metadata["typeName"])
            scale = self._get_column_type_scale(column_metadata["typeName"])
            column_metadata["length"] = length
            column_metadata["scale"] = scale
            column_metadata["typeName"] = column_metadata["typeName"].upper()
            if length and scale:
                column_metadata["typeName"] = column_metadata["typeName"].replace(
                    f"({length},{scale})", ""
                )
            elif length:
                column_metadata["typeName"] = column_metadata["typeName"].replace(
                    f"({length})", ""
                )

        return columns_metadata_list

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
                    "scale": None
                },
                ...
            ]
        }
        """

        primary_keys = self.mysql_consumer.get_table_primary_keys(table_name)
        columns = self.mysql_consumer.get_table_schema(table_name)
        columns_rows = (
            columns.withColumnRenamed("col_name", "name")
            .withColumnRenamed("col_type", "typeName")
            .collect()
        )
        columns_metadata_list = self.format_columns_dict(
            [row.asDict() for row in columns_rows]
        )

        return {"primaryKeyColumnNames": primary_keys, "columns": columns_metadata_list}
