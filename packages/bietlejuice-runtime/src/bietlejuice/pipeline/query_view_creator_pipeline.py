import json
import logging

import sqlglot

from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.db.database_enum import DatabaseEnum
from bietlejuice.base.pipeline.query_view_sync import (
    QueryViewSyncTargetEnum,
    normalize_query_view_sync_config,
)
from bietlejuice.base.spark.base_spark import BaseDBUtils
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.clients.db_clients.trino_client import TrinoClient
from bietlejuice.pipeline.abstract_pipeline import AbstractPipeline
from bietlejuice.services.metastore_services.metastore_service_factory import (
    MetastoreServiceFactory,
)

DELTA_CATALOG = "delta"

logger = logging.getLogger(__name__)


class QueryViewCreatorPipeline(AbstractPipeline):
    """
    Pipeline responsible for creating views on Databricks and optionally on Trino.
    This pipeline creates non-materialized views that are automatically overwritten on every execution.
    """

    def __init__(
        self,
        database_name: str,
        view_name: str,
        layer: str,
        query: str,
        query_template_params: dict = None,
        spark_session_configs: dict = None,
        env: str = None,
        spark=None,
        table_privileges: TablePrivileges = None,
        sync: list[str] = None,
        sql_dialect: str = None,
    ):
        """
        :param database_name: database name to create the view
        :param view_name: view name to be created
        :param layer: layer of pipeline (dw/enrich)
        :param query: SQL query for the view definition
        :param query_template_params: dict of parameters to apply to query template
        :param spark_session_configs: custom config parameters to be set in spark session
        :param env: environment (forno/prod)
        :param spark: Spark session object
        :param table_privileges: TablePrivileges object to apply view privileges after creation
        :param sync: target systems where the view must be created
        :param sql_dialect: source SQL dialect for the query
        """
        sync_config = normalize_query_view_sync_config(
            {
                "sync": sync,
                "sql_dialect": sql_dialect,
            }
        )

        self.database_name = database_name
        self.view_name = view_name
        self.layer = layer
        self.query = query
        self.query_template_params = query_template_params or {}
        self.spark_session_configs = spark_session_configs or {}
        self.env = env
        self.spark = spark
        self.table_privileges = table_privileges
        self.sync = sync_config.sync
        self.sql_dialect = sync_config.sql_dialect

    def run(self):
        """
        Creates views on the configured targets based on the provided SQL query.
        The views are automatically overwritten if they already exist.
        """
        formatted_query = self.query.format(**self.query_template_params)

        views_created = []
        spark_client = None

        for target in self.sync:
            target_query = self._get_query_for_target(formatted_query, target)
            if target == QueryViewSyncTargetEnum.DATABRICKS.value:
                spark_client = spark_client or SparkClient()
                self._create_databricks_view(spark_client, target_query)
                views_created.append("Databricks")
            elif target == QueryViewSyncTargetEnum.TRINO.value:
                self._create_trino_view(target_query)
                views_created.append("Trino")

        if (
            self.table_privileges
            and QueryViewSyncTargetEnum.DATABRICKS.value in self.sync
            and UnityCatalogHelper.is_cluster_unity_catalog_enabled()
        ):
            self.table_privileges.apply()

        logger.info(
            f"Successfully created view {self.database_name}.{self.view_name} "
            f"on {', '.join(views_created)}"
        )

    def _get_query_for_target(self, formatted_query: str, target: str) -> str:
        if self.sql_dialect == target:
            return formatted_query

        return sqlglot.transpile(formatted_query, read=self.sql_dialect, write=target)[
            0
        ]

    def _create_databricks_database(self, spark_client: SparkClient):
        """Create the database on Databricks if it doesn't exist."""
        try:
            spark_metastore_service = (
                MetastoreServiceFactory.create_loader_metastore_service(spark_client)
            )
            spark_metastore_service.create_database(self.database_name)
            logger.info(
                f"Successfully ensured database {self.database_name} exists on Databricks"
            )
        except Exception as e:
            logger.error(
                f"Failed to create database {self.database_name} on Databricks: {str(e)}"
            )
            raise

    def _create_databricks_view(self, spark_client: SparkClient, formatted_query: str):
        """Create or replace the view on Databricks."""

        try:
            self._create_databricks_database(spark_client)

            create_view_sql = f"""
            CREATE OR REPLACE VIEW {self.database_name}.{self.view_name} AS
            {formatted_query}
            """

            spark_client.conn.sql(create_view_sql)
            logger.info(
                f"Successfully created/replaced view {self.database_name}.{self.view_name} on Databricks"
            )
        except Exception as e:
            logger.error(
                f"Failed to create view {self.database_name}.{self.view_name} on Databricks: {str(e)}"
            )
            raise

    def get_trino_client(self) -> TrinoClient:
        """
        Retrieves the Trino client using the credentials from Databricks Utils. The catalog will point to DELTA_CATALOG.
        """
        base_dbutils = BaseDBUtils()
        dbutils = base_dbutils.get_dbutils()

        trino_credentials = json.loads(
            dbutils.secrets.get(scope="quintoandar", key=DatabaseEnum.TRINO)
        )

        return TrinoClient(
            host=trino_credentials["host"],
            port=trino_credentials["port"],
            user=trino_credentials["user"],
            password=trino_credentials["pwd"],
            catalog=DELTA_CATALOG,
            client_tags=["pipeline"],
        )

    def _create_trino_schema(self, trino_client: TrinoClient):
        """Create the schema on Trino if it doesn't exist."""
        try:
            trino_client.run(
                f"CREATE SCHEMA IF NOT EXISTS {DELTA_CATALOG}.{self.database_name}"
            )
            logger.info(
                f"Successfully ensured schema {self.database_name} exists on Trino"
            )
        except Exception as e:
            logger.error(
                f"Failed to create schema {self.database_name} on Trino: {str(e)}"
            )
            raise

    def _create_trino_view(self, formatted_query: str):
        """Create or replace the view on Trino."""

        try:
            trino_client = self.get_trino_client()

            self._create_trino_schema(trino_client)

            trino_create_view_statement = f"""
            CREATE OR REPLACE VIEW {self.database_name}.{self.view_name} AS
            {formatted_query}
            """

            trino_client.run(trino_create_view_statement)

            logger.info(
                f"Successfully created/replaced view {self.database_name}.{self.view_name} on Trino"
            )

        except Exception as e:
            logger.error(
                f"Failed to create view {self.database_name}.{self.view_name} on Trino: {str(e)}"
            )
            raise
