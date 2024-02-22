from abc import ABC, abstractmethod
from pyspark.sql import DataFrame


class CdcSchemaTreatment(ABC):
    @abstractmethod
    def treat_dataframe(
        schema: str, table_name: str, transactional_dataframe: DataFrame
    ) -> DataFrame:
        """Treats the dataframe columns of the transactional layer, such as converting unix timestamps to datetime."""
        pass
