import os

from py4j.protocol import Py4JError, Py4JJavaError
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.databricks.table_privilege_type_enum import TablePrivilegeTypeEnum
from bietlejuice.base.spark.base_spark import BaseSparkContext


class UnityCatalogHelper:
    CATALOGS = {"forno": "quintoandar_forno", "prod": "quintoandar_prod"}
    logger = QuintoAndarLogger("UnityCatalogHelper")

    @staticmethod
    def get_current_catalog() -> str:
        """Returns the current catalog in use"""

        try:
            # This is the most reliable way to get the current catalog, but it doesn't work in Unity Catalog Shared Clusters,
            # which is why we have the fallback below
            return BaseSparkContext.spark.catalog.currentCatalog()
        except Py4JError:
            if UnityCatalogHelper.is_cluster_unity_catalog_enabled():
                return BaseSparkContext.spark.conf.get(
                    "spark.databricks.sql.initial.catalog.namespace"
                )
            else:
                return "hive_metastore"

    @staticmethod
    def is_default_catalog_using_unity() -> bool:
        """Returns true if the cluster is configured to use a catalog that supports Unity Catalog"""

        return (
            UnityCatalogHelper.get_current_catalog()
            in UnityCatalogHelper.CATALOGS.values()
        )

    @staticmethod
    def is_cluster_unity_catalog_enabled() -> bool:
        """Returns true if the cluster could use Unity Catalog (even if it doesn't by default).
        On non-Databricks runtimes (e.g. EMR) the config is absent and we return False.
        """
        try:
            return (
                BaseSparkContext.spark.conf.get("spark.databricks.unityCatalog.enabled")
                == "true"
            )
        except Py4JJavaError:
            return False

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

    @staticmethod
    def grant_table_permission(
        privilege_type: TablePrivilegeTypeEnum,
        table_name: str,
        principal: str,
        catalog: str = None,
    ) -> None:
        """Grants permissions for a user or group on a table in Unity Catalog"""
        if not catalog:
            catalog = UnityCatalogHelper.get_environment_unity_catalog()

        BaseSparkContext.spark.sql(
            f"GRANT {privilege_type.value} ON TABLE {catalog}.{table_name} TO `{principal}`"
        )
        UnityCatalogHelper.logger.info(
            f"Granted {privilege_type.value} on {catalog}.{table_name} to {principal}"
        )

    @staticmethod
    def table_or_schema_has_data_contract_tag(table_name: str, catalog: str = None):
        """Checks if a table or the table schema has the data contract tag"""
        if not catalog:
            catalog = UnityCatalogHelper.get_environment_unity_catalog()

        schema = table_name.split(".")[0]

        tags = BaseSparkContext.spark.sql(
            f"""
        SELECT
            tt.tag_name,
            tt.tag_value
        FROM system.information_schema.table_tags tt
        WHERE tt.catalog_name = '{catalog}' AND (tt.schema_name || "." || tt.table_name) = '{table_name}'
        UNION ALL
        SELECT
            st.tag_name,
            st.tag_value
        FROM system.information_schema.schema_tags st
        WHERE st.catalog_name = '{catalog}' AND st.schema_name = '{schema}'"""
        ).collect()

        is_data_contract_managed = False
        data_contract_id = None

        for tag_name, tag_value in tags:
            if tag_name == "data_contract_managed":
                is_data_contract_managed = True
            elif tag_name == "data_contract_id":
                data_contract_id = tag_value

        if is_data_contract_managed:
            UnityCatalogHelper.logger.info(
                f"Table {catalog}.{table_name} has a Data Contract managing the permissions data_contract_id={data_contract_id}"
            )
            return True

        UnityCatalogHelper.logger.info(
            f"Table {catalog}.{table_name} does not have a Data Contract."
        )
        return False
