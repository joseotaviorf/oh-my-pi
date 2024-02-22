from typing import List

from bietlejuice.base.cdc.primary_key_identifiers.primary_key_identifier import (
    PrimaryKeyIdentifier,
)
from bietlejuice.base.cdc.schema_treatment.mysql_cdc_schema_finder import (
    MySqlCdcSchemaFinder,
)


class MySqlPrimaryKeyIdentifier(PrimaryKeyIdentifier):
    def __init__(self, schema_finder: MySqlCdcSchemaFinder) -> None:
        self.schema_finder = schema_finder

    def find_primary_keys(self, schema: str, table_name: str) -> List[str]:
        try:
            latest_table_change = self.schema_finder.find_latest_table_definition(
                schema, table_name
            )
        except ValueError:
            raise ValueError(
                f"The primary keys of the table {schema}.{table_name} could not be automatically identified,"
                "because it was not found in the schema changes topic. Please, provide the primary keys manually in DAG Declaration file."
            )

        return latest_table_change["primaryKeyColumnNames"]
