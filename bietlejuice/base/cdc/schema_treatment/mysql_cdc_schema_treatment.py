from typing import Optional
from pyspark.sql import DataFrame
from pyspark.sql.functions import col, to_timestamp, to_date
from bietlejuice.base.cdc.schema_treatment.cdc_schema_treatment import (
    CdcSchemaTreatment,
)
from bietlejuice.base.cdc.schema_treatment.mysql_cdc_schema_finder import (
    MySqlCdcSchemaFinder,
)


class MySqlCdcSchemaTreatment(CdcSchemaTreatment):
    TYPE_MAPPING = {
        "SMALLINT": "int",
        "MEDIUMINT": "int",
        "INT": "int",
        "BIGINT": "bigint",
        "FLOAT": "double",
        "DOUBLE": "double",
        "TINYBLOB": "binary",
        "BLOB": "binary",
        "MEDIUMBLOB": "binary",
        "LONGBLOB": "binary",
        "BINARY": "binary",
        "VARBINARY": "binary",
    }

    def __init__(
        self,
        schema_finder: MySqlCdcSchemaFinder,
        datalake_table_schema: str,
        transactional_datatype_overrides: dict,
    ) -> None:
        self.schema_finder = schema_finder
        self.datalake_table_schema = datalake_table_schema
        self.transactional_datatype_overrides = transactional_datatype_overrides

    def treat_dataframe(
        self, table_name: str, transactional_dataframe: DataFrame
    ) -> DataFrame:
        latest_table_change = self._try_find_latest_table_definition(table_name)
        if latest_table_change:
            transactional_dataframe = self._treat_columns_from_latest_table_change(
                latest_table_change,
                transactional_dataframe,
                self.transactional_datatype_overrides,
            )

        datalake_dataframe = self._try_find_existing_datalake_table(
            self.datalake_table_schema, table_name
        )
        if datalake_dataframe:
            transactional_dataframe = self._treat_columns_from_existing_datalake_table(
                datalake_dataframe, transactional_dataframe
            )

        return transactional_dataframe

    def _try_find_latest_table_definition(self, table_name: str) -> Optional[dict]:
        """Try to find the latest table definition, if it exists."""
        try:
            return self.schema_finder.find_latest_table_definition(table_name)
        except ValueError:
            return None

    def _treat_columns_from_latest_table_change(
        self, latest_table_change: dict, transactional_dataframe: DataFrame
    ) -> DataFrame:
        """Forces the columns of the transactional dataframe to match the latest table DDL change in the source database."""

        transactional_dataframe = self._apply_declared_types(transactional_dataframe)

        transactional_dataframe = self._treat_timestamp_columns(
            transactional_dataframe, latest_table_change
        )
        transactional_dataframe = self._treat_boolean_columns(
            transactional_dataframe, latest_table_change
        )
        transactional_dataframe = self._treat_decimal_columns(
            transactional_dataframe, latest_table_change
        )
        transactional_dataframe = self._map_column_types(
            transactional_dataframe, latest_table_change
        )

        return transactional_dataframe

    def _treat_columns_from_existing_datalake_table(
        self, datalake_dataframe: DataFrame, transactional_dataframe: DataFrame
    ) -> DataFrame:
        """Forces the columns of the transactional dataframe to match the schema of the existing datalake table, to avoid type mismatches."""

        transactional_dataframe = self._treat_timestamp_columns_from_existing_datalake_table(
            transactional_dataframe, datalake_dataframe
        )
        transactional_dataframe = self._cast_differing_types(
            transactional_dataframe, datalake_dataframe
        )

        return transactional_dataframe

    def _treat_timestamp_columns(
        self, transactional_dataframe: DataFrame, latest_table_change: dict
    ) -> DataFrame:
        """
        CDC saves date and datetime columns as unix timestamps. This method converts them back to datetime, identifying
        the columns that are timestamps by looking at the latest DDL change in the table schema, and treating them accordingly.
        """
        days_unix_columns = []
        milliseconds_unix_columns = []
        string_columns = []

        for column in latest_table_change["columns"]:
            if (
                column["name"] not in transactional_dataframe.columns
                or column["name"] in self.transactional_datatype_overrides.keys()
            ):
                continue
            if column["typeName"] == "DATE":
                days_unix_columns.append(column["name"])
            elif column["typeName"] == "DATETIME":
                milliseconds_unix_columns.append(column["name"])
            elif column["typeName"] == "TIMESTAMP":
                string_columns.append(column["name"])

        return self._treat_timestamp_columns_from_column_lists(
            transactional_dataframe,
            days_unix_columns,
            milliseconds_unix_columns,
            string_columns,
        )

    def _treat_timestamp_columns_from_existing_datalake_table(
        self, transactional_dataframe: DataFrame, datalake_dataframe: DataFrame
    ) -> DataFrame:
        """
        CDC saves date and datetime columns as unix timestamps. This method converts them back to datetime, identifying
        the columns that are timestamps by looking at the schema of the existing datalake table, and treating them accordingly.
        """
        days_unix_columns = []
        milliseconds_unix_columns = []
        string_columns = []

        for column in datalake_dataframe.columns:
            if column not in transactional_dataframe.columns or transactional_dataframe.schema[
                column
            ].dataType.typeName() in (
                "date",
                "timestamp",
            ):
                continue

            if datalake_dataframe.schema[column].dataType.typeName() == "date":
                days_unix_columns.append(column)
            elif (
                datalake_dataframe.schema[column].dataType.typeName() == "timestamp"
                and transactional_dataframe.schema[column].dataType.typeName()
                == "string"
            ):
                string_columns.append(column)
            elif datalake_dataframe.schema[column].dataType.typeName() == "timestamp":
                milliseconds_unix_columns.append(column)

        return self._treat_timestamp_columns_from_column_lists(
            transactional_dataframe,
            days_unix_columns,
            milliseconds_unix_columns,
            string_columns,
        )

    def _treat_timestamp_columns_from_column_lists(
        self,
        transactional_dataframe: DataFrame,
        days_unix_columns: list,
        milliseconds_unix_columns: list,
        string_columns: list,
    ) -> DataFrame:
        """CDC saves date and datetime columns as unix timestamps. This method converts them back to datetime"""

        for column in days_unix_columns:
            transactional_dataframe = transactional_dataframe.withColumn(
                column, to_date(to_timestamp(col(column) * 24 * 60 * 60))
            )
        for column in milliseconds_unix_columns:
            transactional_dataframe = transactional_dataframe.withColumn(
                column, to_timestamp(col(column) / 1000)
            )
        for column in string_columns:
            transactional_dataframe = transactional_dataframe.withColumn(
                column, to_timestamp(col(column))
            )

        return transactional_dataframe

    def _treat_boolean_columns(
        self, transactional_dataframe: DataFrame, latest_table_change: dict
    ) -> DataFrame:
        for column in latest_table_change["columns"]:
            if (
                column["name"] not in transactional_dataframe.columns
                or column["name"] in self.transactional_datatype_overrides.keys()
            ):
                continue
            if column["typeName"] not in ("BIT", "TINYINT"):
                continue
            if column["length"] == 1:
                transactional_dataframe = transactional_dataframe.withColumn(
                    column["name"], col(column["name"]).cast("boolean")
                )
            else:
                transactional_dataframe = transactional_dataframe.withColumn(
                    column["name"], col(column["name"]).cast("int")
                )
        return transactional_dataframe
