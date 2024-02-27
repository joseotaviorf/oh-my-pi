from pyspark.sql import DataFrame
from pyspark.sql.functions import col, to_timestamp, to_date
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

        for column in latest_table_change["columns"]:
            if column["typeName"] == "DATE":  # Comes in days
                transactional_dataframe = transactional_dataframe.withColumn(
                    column["name"],
                    to_date(to_timestamp(col(column["name"]) * 24 * 60 * 60)),
                )
            elif column["typeName"] == "DATETIME":  # Comes in milliseconds
                transactional_dataframe = transactional_dataframe.withColumn(
                    column["name"], to_timestamp(col(column["name"]) / 1000)
                )
            elif column["typeName"] == "TIMESTAMP":  # Comes as string
                transactional_dataframe = transactional_dataframe.withColumn(
                    column["name"], to_timestamp(col(column["name"]))
                )

        return transactional_dataframe
