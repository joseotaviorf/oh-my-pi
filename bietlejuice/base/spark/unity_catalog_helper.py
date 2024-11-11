from bietlejuice.base.spark import BaseSparkContext


class UnityCatalogHelper:
    CATALOGS = {"quintoandar_forno", "quintoandar_prod"}

    @staticmethod
    def is_default_catalog_using_unity():
        return (
            BaseSparkContext.spark.catalog.currentCatalog()
            in UnityCatalogHelper.CATALOGS
        )

    @staticmethod
    def is_cluster_unity_catalog_enabled():
        return (
            BaseSparkContext.spark.conf.get("spark.databricks.unityCatalog.enabled")
            == "true"
        )
