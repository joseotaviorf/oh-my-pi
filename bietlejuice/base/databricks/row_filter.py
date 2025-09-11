from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.spark import BaseSparkContext

JOB_NAME = "row_filter"

logger = QuintoAndarLogger(JOB_NAME)


class RowFilter:
    """
    Class to represent a row filter for a Databricks table
    """

    def __init__(self, spark=BaseSparkContext.spark) -> None:
        self.spark = spark

    def has_row_filter(self, table_name):
        """
        Checks if a Databricks table has a Row Filter using DESCRIBE TABLE EXTENDED.

        Args:
            table_name (str): The name of the table to check.

        Returns:
            bool: True if the table has a Row Filter, False otherwise.
        """
        try:
            df_desc = self.spark.sql(f"DESCRIBE TABLE EXTENDED {table_name}")
            row_filter_row = df_desc.filter("col_name = 'Row Filter'").collect()
            if len(row_filter_row) > 0:
                logger.info(f"The table '{table_name}' has a Row Filter.")
                return True
            else:
                logger.info(f"The table '{table_name}' does not have a Row Filter.")
                return False
        except Exception as e:
            logger.error(f"An error occurred while checking the table: {e}")
            return False

    def apply_row_filter(self, table_name, column_key, function_name):
        """
        Applies a Row Filter to a Databricks table.

        Args:
            table_name (str): The name of the table to apply the Row Filter to.
            column_key (str): The column key for the Row Filter.
            function_name (str): The function name for the Row Filter.
        Returns:
            None
        """
        try:
            self.spark.sql(
                f"""
                ALTER TABLE {table_name}
                SET ROW FILTER {function_name} ON
                ({column_key})
                """
            )
            logger.info(
                f"Row Filter '{function_name}' applied on table '{table_name}'."
            )

        except Exception as e:
            logger.error(f"An error occurred while applying the Row Filter: {e}")
