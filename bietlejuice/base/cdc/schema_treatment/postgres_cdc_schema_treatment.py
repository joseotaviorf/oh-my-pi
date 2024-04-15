from pyspark.sql import DataFrame
from typing import Optional
from pyspark.sql.functions import col, to_timestamp, to_date
from bietlejuice.base.cdc.schema_treatment.cdc_schema_treatment import (
    CdcSchemaTreatment,
)
from bietlejuice.base.cdc.schema_treatment.postgres_cdc_schema_finder import (
    PostgresCdcSchemaFinder,
)


class PostgresCdcSchemaTreatment(CdcSchemaTreatment):
    TYPE_MAPPING = {"smallint": "int", "integer": "int"}

    def __init__(
        self, schema_finder: PostgresCdcSchemaFinder, datalake_table_schema: str
    ) -> None:
        self.schema_finder = schema_finder
        self.datalake_table_schema = datalake_table_schema

    def treat_dataframe(
        self, table_name: str, transactional_dataframe: DataFrame
    ) -> DataFrame:
        latest_table_change = self._try_find_latest_table_definition(table_name)
        if latest_table_change:
            transactional_dataframe = self._treat_columns_from_latest_table_change(
                latest_table_change, transactional_dataframe
            )

        datalake_dataframe = self._try_finding_existing_datalake_table(
            self.datalake_table_schema, table_name
        )
        if datalake_dataframe:
            transactional_dataframe = self._treat_columns_from_existing_datalake_table(
                datalake_dataframe, transactional_dataframe
            )

        return transactional_dataframe

    def _try_find_latest_table_definition(self, table_name: str) -> Optional[dict]:
        """Try to find the latest table definition, if it exists."""
        return self.schema_finder.find_latest_table_definition(table_name)

    def _treat_columns_from_latest_table_change(
        self, latest_table_change: dict, transactional_dataframe: DataFrame
    ) -> DataFrame:
        """Forces the columns of the transactional dataframe to match the latest table DDL change in the source database, which is found in the Postgres database."""
        transactional_dataframe = self._treat_timestamp_columns(
            transactional_dataframe, latest_table_change
        )
        transactional_dataframe = self._treat_decimal_columns(
            transactional_dataframe, latest_table_change
        )
        transactional_dataframe = self._map_column_types(
            transactional_dataframe, latest_table_change
        )

        return transactional_dataframe

    def _treat_timestamp_columns(
        self, transactional_dataframe: DataFrame, latest_table_change: dict
    ) -> DataFrame:
        """
        CDC saves timestamp without time zone in unix microseconds, date in days since the epoch and timestamp with time zone
        as a string. This method converts those columns into timestamp by applying the necessary transformations.
        """
        for column in latest_table_change["columns"]:
            if column["name"] not in transactional_dataframe.columns:
                continue
            if column["typeName"] == "timestamp without time zone":
                transactional_dataframe = transactional_dataframe.withColumn(
                    column["name"], to_timestamp(col(column["name"]) / (1000 * 1000))
                )
            elif column["typeName"] == "date":
                transactional_dataframe = transactional_dataframe.withColumn(
                    column["name"],
                    to_date(to_timestamp(col(column["name"]) * 24 * 60 * 60)),
                )
            elif column["typeName"] == "timestamp with time zone":
                transactional_dataframe = transactional_dataframe.withColumn(
                    column["name"], to_timestamp(col(column["name"]))
                )

        return transactional_dataframe

    def _treat_columns_from_existing_datalake_table(
        self, datalake_dataframe: DataFrame, transactional_dataframe: DataFrame
    ) -> DataFrame:
        """
        To persist the data type from previously saved table on datalake, we must apply the necessary transformations.
        """
        transactional_dataframe = self._treat_timestamp_columns_from_existing_datalake_table(
            transactional_dataframe, datalake_dataframe
        )
        transactional_dataframe = self._cast_differing_types(
            transactional_dataframe, datalake_dataframe
        )

        return transactional_dataframe

    def _treat_timestamp_columns_from_existing_datalake_table(
        self, transactional_dataframe: DataFrame, datalake_dataframe: DataFrame
    ) -> DataFrame:
        """
        Verifies if the column data type from the previously datalake table matches with the column from transactional table, if not
        apply the necessary transformation.
        """
        for column in datalake_dataframe.columns:
            if column["name"] not in transactional_dataframe.columns:
                continue
            if (
                datalake_dataframe.schema[column].dataType.typeName() == "timestamp"
                and transactional_dataframe.schema[column].dataType.typeName == "string"
            ):
                transactional_dataframe = transactional_dataframe.withColumn(
                    column["name"], to_timestamp(col(column["name"]))
                )
            elif (
                datalake_dataframe.schema[column].dataType.typeName() == "date"
                and transactional_dataframe.schema[column].dataType.typeName == "string"
            ):
                transactional_dataframe = transactional_dataframe.withColumn(
                    column["name"],
                    to_date(to_timestamp(col(column["name"]) * 24 * 60 * 60)),
                )

        return transactional_dataframe
