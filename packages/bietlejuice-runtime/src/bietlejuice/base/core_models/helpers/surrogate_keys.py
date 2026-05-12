from typing import List, Union

from pyspark.sql import DataFrame
from pyspark.sql.functions import col, concat_ws, lit, sha2


class SurrogateKeysHelper:
    # Common utility methods for Spark jobs
    @staticmethod
    def generate_surrogate_key(
        df: DataFrame, entity_type: str, id_column: Union[str, List[str]] = "id_entity"
    ) -> DataFrame:
        """
        Generate surrogate key for the DataFrame using SHA256 hash.
        Common function used across all core model Spark jobs.

        Args:
            df: DataFrame to add surrogate key to
            entity_type: Entity type constant (e.g., "VISIT", "OFFER", "CONTRACT")
            id_column: Column name(s) containing the entity ID. Can be a single column name (string)
                      or multiple column names (list of strings)

        Returns:
            DataFrame: DataFrame with surrogate key column added
        """
        # Handle both single column (string) and multiple columns (list)
        if isinstance(id_column, str):
            columns_to_concat = [lit(entity_type), col(id_column)]
        elif isinstance(id_column, list):
            if not id_column:  # Empty list
                raise ValueError("id_column list cannot be empty")
            columns_to_concat = [lit(entity_type)] + [
                col(column) for column in id_column
            ]
        else:
            raise TypeError(
                f"id_column must be str or list of str, got {type(id_column)}"
            )

        return df.withColumn(
            "surrogate_key", sha2(concat_ws("||", *columns_to_concat), 256)
        )
