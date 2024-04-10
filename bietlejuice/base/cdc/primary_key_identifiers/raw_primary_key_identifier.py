from typing import List, Optional

from bietlejuice.base.cdc.primary_key_identifiers.primary_key_identifier import (
    PrimaryKeyIdentifier,
)
from bietlejuice.base.cdc.schema_treatment.cdc_schema_finder import CdcSchemaFinder
from bietlejuice.base.spark.base_spark import BaseSparkContext
from delta.tables import DeltaTable
from pyspark.sql.utils import AnalysisException


class RawPrimaryKeyIdentifier(PrimaryKeyIdentifier):
    def __init__(
        self, schema_finder: CdcSchemaFinder, datalake_table_schema: str
    ) -> None:
        self.schema_finder = schema_finder
        self.datalake_table_schema = datalake_table_schema

    def find_primary_keys(self, table_name: str) -> List[str]:
        primary_keys = self._try_find_existing_delta_table_pks(
            self.datalake_table_schema, table_name
        )
        if primary_keys:
            return primary_keys

        try:
            return self.schema_finder.find_latest_table_definition(table_name)[
                "primaryKeyColumnNames"
            ]
        except ValueError:
            raise ValueError(
                f"The primary keys of the table {table_name} could not be automatically identified,"
                "because it was not found in the schema changes topic. Please, provide the primary keys manually in DAG Declaration file."
            )

    def _try_find_existing_delta_table_pks(
        self, datalake_table_schema: str, table_name: str
    ) -> Optional[list]:
        """Try to find the primary keys in the metadata of a saved datalake table, if it exists."""
        try:
            spark = BaseSparkContext.spark
            delta_table = DeltaTable.forName(
                spark, f"{datalake_table_schema}.{table_name}"
            )
            return (
                delta_table.detail().collect()[0].properties["primary_keys"].split(",")
            )
        except AnalysisException:
            return None
        except KeyError:
            return None
