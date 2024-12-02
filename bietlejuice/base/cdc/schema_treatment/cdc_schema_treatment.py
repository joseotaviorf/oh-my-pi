from abc import ABC, abstractmethod
from typing import Optional
from pyspark.sql import DataFrame
from pyspark.sql.functions import col
from pyspark.sql.utils import AnalysisException

from bietlejuice.base.spark.base_spark import BaseSparkContext


class CdcSchemaTreatment(ABC):
    @abstractmethod
    def treat_dataframe(
        schema: str, table_name: str, transactional_dataframe: DataFrame
    ) -> DataFrame:
        """Treats the dataframe columns of the transactional layer, such as converting unix timestamps to datetime."""
        pass

    def _cast_differing_types(
        self, transactional_dataframe: DataFrame, datalake_dataframe: DataFrame
    ) -> DataFrame:
        """Cast columns in the transactional dataframe to the same type as the datalake dataframe, to avoid type mismatches"""

        for column in datalake_dataframe.columns:
            if column not in transactional_dataframe.columns:
                continue
            if (
                transactional_dataframe.schema[column].dataType
                != datalake_dataframe.schema[column].dataType
            ):
                transactional_dataframe = transactional_dataframe.withColumn(
                    column, col(column).cast(datalake_dataframe.schema[column].dataType)
                )
        return transactional_dataframe

    def _try_find_existing_datalake_table(
        self, datalake_table_schema: str, table_name: str
    ) -> Optional[DataFrame]:
        """Try to find the datalake table, if it exists."""
        try:
            return BaseSparkContext.spark.table(f"{datalake_table_schema}.{table_name}")
        except AnalysisException:
            return None

    def _map_column_types(
        self, transactional_dataframe: DataFrame, latest_table_change: dict
    ) -> DataFrame:
        for column in latest_table_change["columns"]:
            if (
                column["name"] not in transactional_dataframe.columns
                or column["name"] in self.transactional_datatype_overrides.keys()
            ):
                continue
            if column["typeName"] in self.TYPE_MAPPING:
                transactional_dataframe = transactional_dataframe.withColumn(
                    column["name"],
                    col(column["name"]).cast(self.TYPE_MAPPING[column["typeName"]]),
                )
        return transactional_dataframe

    def _treat_decimal_columns(
        self, transactional_dataframe: DataFrame, latest_table_change: dict
    ) -> DataFrame:
        """
        CDC saves decimal and numeric data types as a float64. This method converts to decimal again.
        """
        for column in latest_table_change["columns"]:
            if (
                column["name"] not in transactional_dataframe.columns
                or column["name"] in self.transactional_datatype_overrides.keys()
            ):
                continue
            if column["typeName"].upper() in ("DECIMAL", "NUMERIC"):
                type = f"decimal({column['length']}, {column['scale']})"
                if column["length"] is None or column["scale"] is None:
                    type = "decimal(38, 18)"
                transactional_dataframe = transactional_dataframe.withColumn(
                    column["name"], col(column["name"]).cast(type)
                )

        return transactional_dataframe

    def _apply_declared_types(self, transactional_dataframe: DataFrame) -> DataFrame:
        """Applies the declared types to the transactional dataframe, if they exist."""
        for column, datatype in self.transactional_datatype_overrides.items():
            if column not in transactional_dataframe.columns:
                continue
            transactional_dataframe = transactional_dataframe.withColumn(
                column, col(column).cast(datatype)
            )
        return transactional_dataframe
