from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.spark.base_spark import BaseSparkContext

logger = QuintoAndarLogger("DeltaLoader")


class DeltaLoader:
    """Class for loading data into a Delta table"""

    def vacuum_table(self, table_name: str, retention_hours: int) -> None:
        """Vacuum a Delta table"""
        spark = BaseSparkContext.spark
        command = f"VACUUM {table_name} RETAIN {retention_hours} HOURS"
        logger.info(f"Running vacuum with command {command}")
        spark.sql(command)
        logger.info(f"Vacuum successful for table {table_name}")

    def optimize_table(self, table_name: str, z_order_by: list = None) -> None:
        """Optimize a Delta table, optionally using ZORDER BY"""
        spark = BaseSparkContext.spark
        command = f"OPTIMIZE {table_name}"
        if z_order_by:
            command += f" ZORDER BY {','.join(z_order_by)}"
        logger.info(f"Running optimize with command {command}")
        spark.sql(command)
        logger.info(f"Optimize successful for table {table_name}")
