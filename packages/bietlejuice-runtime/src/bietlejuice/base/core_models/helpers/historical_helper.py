from pyspark.sql import DataFrame, SparkSession
from pyspark.sql.functions import col, lit

CDC_COLUMNS = ["op_cdc", "ts_database_transaction", "ts_cdc_transaction"]


class HistoricalHelper:
    """Reusable helper for core model historical tables.

    Provides utilities for loading data from the CDC transactional layer
    and enriching DataFrames with CDC metadata columns. Any core model
    Spark job can import this helper to build historical tracking tables
    without modifying the CDC pipeline itself.
    """

    @staticmethod
    def load_transactional_data(
        spark: SparkSession,
        table_name: str,
        args,
        date_column: str = "ts_database_transaction",
    ) -> DataFrame:
        """Load data from a CDC transactional table with date-range filtering.

        Args:
            spark: SparkSession instance
            table_name: Fully qualified transactional table name
                (e.g. ``datalake_company_transactional.company``)
            args: Parsed job arguments containing load_start_date / load_end_date
            date_column: Column to filter on (default ``ts_database_transaction``)

        Returns:
            DataFrame filtered to the requested date range
        """
        df = spark.read.table(table_name)

        if (
            args.load_start_date is not None
            and args.load_start_date != ""
            and args.load_end_date is not None
            and args.load_end_date != ""
        ):
            df = df.filter(
                (
                    col(date_column).cast("date")
                    >= lit(args.load_start_date).cast("date")
                )
                & (
                    col(date_column).cast("date")
                    <= lit(args.load_end_date).cast("date")
                )
            )

        return df

    @staticmethod
    def select_cdc_columns(transactional_df: DataFrame, alias: str) -> list:
        """Return CDC column expressions from a transactional DataFrame.

        Args:
            transactional_df: DataFrame loaded from a transactional table
            alias: Table alias used in the join (e.g. ``"c"``)

        Returns:
            List of Column expressions for ``op_cdc``, ``ts_database_transaction``
            and ``ts_cdc_transaction``
        """
        return [col(f"{alias}.{c}") for c in CDC_COLUMNS]
