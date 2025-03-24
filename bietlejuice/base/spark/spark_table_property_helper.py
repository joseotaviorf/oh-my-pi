from bietlejuice.base.spark import BaseSparkContext


class SparkTablePropertyHelper:
    @staticmethod
    def get_property(
        table_name: str, property_name: str, spark=BaseSparkContext.spark
    ) -> str:
        """
        Get a property from a table.
        """
        return SparkTablePropertyHelper.get_table_properties(table_name, spark).get(
            property_name
        )

    @staticmethod
    def get_table_properties(table_name, spark=BaseSparkContext.spark) -> dict:
        """
        Get all properties from a table
        """
        return {
            prop.key: prop.value
            for prop in spark.sql(f"SHOW TBLPROPERTIES {table_name}").collect()
        }

    @staticmethod
    def set_property(
        table_name: str,
        property_name: str,
        property_value: str,
        spark=BaseSparkContext.spark,
    ) -> None:
        """
        Set a property in a table
        """
        spark.sql(
            f"ALTER TABLE {table_name} SET TBLPROPERTIES ('{property_name}'='{property_value}')"
        )
