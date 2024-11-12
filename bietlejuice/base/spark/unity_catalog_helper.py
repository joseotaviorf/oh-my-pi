import os
from bietlejuice.base.spark import BaseSparkContext
from quintoandar_logger import QuintoAndarLogger


class UnityCatalogHelper:
    CATALOGS = {"forno": "quintoandar_forno", "prod": "quintoandar_prod"}
    logger = QuintoAndarLogger("UnityCatalogHelper")

    @staticmethod
    def is_default_catalog_using_unity() -> bool:
        """Returns true if the cluster is configured to use a catalog that supports Unity Catalog"""

        return (
            BaseSparkContext.spark.catalog.currentCatalog()
            in UnityCatalogHelper.CATALOGS.values()
        )

    @staticmethod
    def is_cluster_unity_catalog_enabled() -> bool:
        """Returns true if the cluster could use Unity Catalog (even if it doesn't by default)"""

        return (
            BaseSparkContext.spark.conf.get("spark.databricks.unityCatalog.enabled")
            == "true"
        )

    @staticmethod
    def sync_table_to_unity_catalog(
        table_name: str,
        source_catalog: str = "hive_metastore",
        destination_catalog: str = None,
    ) -> None:
        """
        Syncs a table from one catalog to another, using the Unity Catalog SYNC command.
        If destination_catalog is not provided, it will use catalog that makes the most sense for
        the environment.
        """

        if not destination_catalog:
            destination_catalog = UnityCatalogHelper.get_environment_unity_catalog()

        UnityCatalogHelper.logger.info(
            f"Syncing table {table_name} from {source_catalog} to {destination_catalog}"
        )
        BaseSparkContext.spark.sql(
            f"SYNC TABLE {destination_catalog}.{table_name} FROM {source_catalog}.{table_name}"
        )
        UnityCatalogHelper.logger.info(
            f"Table {table_name} synced from {source_catalog} to {destination_catalog}"
        )

    @staticmethod
    def get_environment_unity_catalog() -> str:
        env = os.environ.get("ENVIRONMENT").lower()
        if env not in UnityCatalogHelper.CATALOGS:
            raise ValueError(f"Environment {env} not supported.")
        return UnityCatalogHelper.CATALOGS[env]
