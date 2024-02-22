from pyspark.sql import DataFrame
from pyspark.sql.functions import col, from_unixtime, to_timestamp
from bietlejuice.base.cdc.schema_treatment.cdc_schema_treatment import (
    CdcSchemaTreatment,
)
from bietlejuice.base.cdc.schema_treatment.mysql_cdc_schema_finder import (
    MySqlCdcSchemaFinder,
)


class MySqlCdcSchemaTreatment(CdcSchemaTreatment):
    def __init__(self, schema_finder: MySqlCdcSchemaFinder) -> None:
        self.schema_finder = schema_finder

    def treat_dataframe(
        self, schema: str, table_name: str, transactional_dataframe: DataFrame
    ) -> DataFrame:
        latest_table_change = self.schema_finder.find_latest_table_definition(
            schema, table_name
        )
        transactional_dataframe = self._treat_timestamp_columns(
            transactional_dataframe, latest_table_change
        )
        return transactional_dataframe

    def _treat_timestamp_columns(
        self, transactional_dataframe: DataFrame, latest_table_change: dict
    ) -> DataFrame:
        """CDC saves date and datetime columns as unix timestamps. This method converts them back to datetime."""

        timestamp_types = ("DATE", "DATETIME")
        timestamp_columns = [
            column["name"]
            for column in latest_table_change["columns"]
            if column["typeName"] in timestamp_types
        ]
        for timestamp_column in timestamp_columns:
            transactional_dataframe = transactional_dataframe.withColumn(
                timestamp_column,
                to_timestamp(from_unixtime(col(timestamp_column) / 1000)),
            )

        return transactional_dataframe
