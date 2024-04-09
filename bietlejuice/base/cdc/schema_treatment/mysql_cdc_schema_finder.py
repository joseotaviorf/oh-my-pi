from bietlejuice.base.cdc.schema_treatment.cdc_schema_finder import CdcSchemaFinder
from bietlejuice.base.spark import BaseSparkContext
from pyspark.sql.functions import explode, col, make_date


class MySqlCdcSchemaFinder(CdcSchemaFinder):
    def __init__(
        self, schema_changes_path: str, schema: str, start_date: str, end_date: str
    ) -> None:
        """
        This class identifies the schema of the table based on the topic that registers schema changes. The path to the topic
        saved on S3 is passed as a parameter. The schema changes are saved in JSON format.
        """

        self.schema_changes_path = schema_changes_path
        self.schema = schema
        self.start_date = start_date
        self.end_date = end_date

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
                },
                ...
            ]
        }
        """

        spark = BaseSparkContext.spark
        schema_changes_df = spark.read.json(self.schema_changes_path)
        table_schema_changes_df = (
            schema_changes_df.select(
                explode(col("tableChanges")).alias("table_change"), "ts_ms"
            )
            .select("table_change.*", "ts_ms")
            .filter(
                make_date(col("year"), col("month"), col("day")).between(
                    self.start_date, self.end_date
                )
            )
            .filter(f'id = \'"{self.schema}"."{table_name}"\'')
        )
        try:
            return (
                table_schema_changes_df.orderBy("ts_ms", ascending=False)
                .limit(1)
                .collect()[0]
                .table.asDict(recursive=True)
            )
        except IndexError:
            raise ValueError(
                f"The schema of the table {self.schema}.{table_name} could not be automatically identified, "
                "because it was not found in the schema changes topic."
            )
