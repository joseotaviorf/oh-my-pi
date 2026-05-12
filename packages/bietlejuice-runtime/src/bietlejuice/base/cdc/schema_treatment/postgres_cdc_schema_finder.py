from bietlejuice.base.cdc.schema_treatment.cdc_schema_finder import CdcSchemaFinder
from bietlejuice.consumers.db_consumers import PostgresConsumer


class PostgresCdcSchemaFinder(CdcSchemaFinder):
    def __init__(self, postgres_consumer: PostgresConsumer) -> None:
        """
        This class identifies the schema of the table, by querying the database.
        """

        self.postgres_consumer = postgres_consumer

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
        primary_keys = self.postgres_consumer.get_table_primary_keys(table_name)
        columns = self.postgres_consumer.get_table_schema(table_name)
        columns_rows = (
            columns.withColumnRenamed("col_name", "name")
            .withColumnRenamed("col_type", "typeName")
            .withColumnRenamed("col_length", "length")
            .withColumnRenamed("col_scale", "scale")
            .collect()
        )
        columns_dict = [row.asDict() for row in columns_rows]

        return {"primaryKeyColumnNames": primary_keys, "columns": columns_dict}
