from typing import List

from bietlejuice.base.cdc.primary_key_identifiers.primary_key_identifier import (
    PrimaryKeyIdentifier,
)
from pyspark.sql.functions import explode, col
from bietlejuice.base.spark import BaseSparkContext


class MySqlPrimaryKeyIdentifier(PrimaryKeyIdentifier):
    def __init__(self, schema_changes_path: str) -> None:
        """
        This class identifies the primary keys of the table based on the topic that registers schema changes. The path to the topic
        saved on S3 is passed as a parameter. The schema changes are saved in JSON format.
        """

        self.schema_changes_path = schema_changes_path

    def find_primary_keys(self, schema: str, table_name: str) -> List[str]:
        spark = BaseSparkContext.spark
        schema_changes_df = spark.read.json(self.schema_changes_path)
        table_schema_changes_df = (
            schema_changes_df.select(
                explode(col("tableChanges")).alias("table_change"), "ts_ms"
            )
            .select("table_change.*", "ts_ms")
            .filter(f'id = \'"{schema}"."{table_name}"\'')
        )
        try:
            latest_table_change = (
                table_schema_changes_df.orderBy("ts_ms", ascending=False)
                .limit(1)
                .collect()[0]
            )
        except IndexError:
            raise ValueError(
                f"The primary keys of the table {schema}.{table_name} could not be automatically identified, because it was not found in the schema changes topic. Please, provide the primary keys manually in DAG Declaration file."
            )

        return latest_table_change.table.primaryKeyColumnNames
