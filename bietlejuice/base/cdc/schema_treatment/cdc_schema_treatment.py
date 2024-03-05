from abc import ABC, abstractmethod
from pyspark.sql import DataFrame
from pyspark.sql.functions import col


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
