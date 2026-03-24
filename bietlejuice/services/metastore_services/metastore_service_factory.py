"""
Factory that returns the appropriate ``MetastoreService`` for the current
environment.

Default behaviour: returns a ``CompositeMetastoreService`` wrapping both
the primary Spark service and the appropriate secondary service so that
every table write is registered in both catalogs.  Falls back to
Spark-only when no secondary catalog is available (local dev).
"""

from __future__ import annotations

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.services.metastore_services.composite_metastore_service import (
    CompositeMetastoreService,
)
from bietlejuice.services.metastore_services.metastore_service import (
    MetastoreService,
)

logger = QuintoAndarLogger("MetastoreServiceFactory")


class MetastoreServiceFactory:
    """Create the correct ``MetastoreService`` for the current environment."""

    @staticmethod
    def create(spark_metastore_service: MetastoreService) -> MetastoreService:
        """Return a (possibly composite) metastore service.

        :param spark_metastore_service: The primary Spark-based service.
        :returns: A ``CompositeMetastoreService`` when multiple catalogs
            are active, or the original service when only Spark is
            available.
        """
        from bietlejuice.base.spark.catalog_strategy_resolver import (
            CatalogStrategyResolver,
        )

        services = CatalogStrategyResolver.get_active_services(spark_metastore_service)

        if len(services) == 1:
            return services[0]

        return CompositeMetastoreService(services)
