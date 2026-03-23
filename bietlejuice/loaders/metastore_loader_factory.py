"""
Factory that creates a ``SparkMetastoreLoader`` backed by the correct
metastore service(s) for the current environment.

Use this instead of directly instantiating
``SparkMetastoreLoader(SparkMetastoreService(SparkClient()))`` to
ensure tables are registered in both Databricks and AWS Glue.
"""

from __future__ import annotations

from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("MetastoreLoaderFactory")


class MetastoreLoaderFactory:
    """Create a ``SparkMetastoreLoader`` with composite catalog support."""

    @staticmethod
    def create(spark_client=None):
        """Return a ``SparkMetastoreLoader`` backed by the composite
        metastore service (Spark + Glue when available).

        :param spark_client: Optional pre-built ``SparkClient``.
            A new instance is created when ``None``.
        """
        from bietlejuice.clients.db_clients import SparkClient
        from bietlejuice.loaders.spark_metastore_loader import (
            SparkMetastoreLoader,
        )
        from bietlejuice.services.metastore_services import (
            SparkMetastoreService,
        )
        from bietlejuice.services.metastore_services.metastore_service_factory import (
            MetastoreServiceFactory,
        )

        if spark_client is None:
            spark_client = SparkClient()

        spark_service = SparkMetastoreService(spark_client)
        composite_service = MetastoreServiceFactory.create(spark_service)
        return SparkMetastoreLoader(composite_service)
