"""
Determines which catalog targets are active at runtime and returns the
appropriate ``MetastoreService`` instances.

Behaviour is **runtime-aware**:

- **Databricks** → primary is Spark/UC, secondary is Glue (boto3)
- **EMR** → primary is Spark/Glue (native), secondary is UC (REST API)
- **Local dev / unknown** → Spark only (no secondary)
"""

from __future__ import annotations

from typing import List

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.services.metastore_services.metastore_service import (
    MetastoreService,
)

logger = QuintoAndarLogger("CatalogStrategyResolver")


class CatalogStrategyResolver:

    @staticmethod
    def get_active_services(
        spark_metastore_service: MetastoreService,
    ) -> List[MetastoreService]:
        """Return the list of metastore services that should receive writes.

        Always includes the Spark metastore service.  Adds the
        appropriate secondary service based on the runtime:

        - Databricks → adds ``GlueMetastoreService``
        - EMR → adds ``UnityCatalogRestMetastoreService``
        """
        import importlib

        services: List[MetastoreService] = [spark_metastore_service]

        runtime_detector = importlib.import_module(
            "bietlejuice.base.spark.runtime_detector"
        ).RuntimeDetector

        if runtime_detector.is_databricks():
            services = CatalogStrategyResolver._add_glue_service(services)
        elif runtime_detector.is_emr():
            services = CatalogStrategyResolver._add_uc_rest_service(services)
        else:
            logger.info(
                "m=get_active_services, runtime=unknown, "
                "msg=no secondary catalog, registering in Spark only"
            )

        return services

    @staticmethod
    def sync_to_secondary_catalog(
        database_name: str,
        table_name: str,
        table_location: str,
        table_schema,
        partitions: list,
        format_str: str = "DELTA",
    ) -> None:
        """Sync a table to the secondary (non-native) catalog.

        Dispatches to the correct helper based on runtime:

        - Databricks → ``GlueCatalogHelper.sync_table_to_glue()``
        - EMR → ``UnityCatalogRestHelper.sync_table_to_uc()``
        - Unknown → no-op
        """
        import importlib

        runtime_detector = importlib.import_module(
            "bietlejuice.base.spark.runtime_detector"
        ).RuntimeDetector

        if runtime_detector.is_databricks():
            glue_helper = importlib.import_module(
                "bietlejuice.base.spark.glue_catalog_helper"
            ).GlueCatalogHelper
            glue_helper.sync_table_to_glue(
                database_name=database_name,
                table_name=table_name,
                table_location=table_location,
                table_schema=table_schema,
                partitions=partitions,
                format_str=format_str,
            )
        elif runtime_detector.is_emr():
            uc_rest_helper = importlib.import_module(
                "bietlejuice.base.spark.unity_catalog_rest_helper"
            ).UnityCatalogRestHelper
            uc_rest_helper.sync_table_to_uc(
                database_name=database_name,
                table_name=table_name,
                table_location=table_location,
                table_schema=table_schema,
                partitions=partitions,
                format_str=format_str,
            )
        else:
            logger.info(
                f"m=sync_to_secondary_catalog, table={database_name}.{table_name}, "
                "runtime=unknown, msg=no secondary catalog configured, skipping"
            )

    # -- Private helpers -----------------------------------------------------

    @staticmethod
    def _add_glue_service(
        services: List[MetastoreService],
    ) -> List[MetastoreService]:
        import importlib

        glue_helper = importlib.import_module(
            "bietlejuice.base.spark.glue_catalog_helper"
        ).GlueCatalogHelper

        if glue_helper.is_glue_catalog_enabled():
            from bietlejuice.services.metastore_services.glue_metastore_service import (
                GlueMetastoreService,
            )

            glue_client = glue_helper.get_glue_client()
            glue_service = GlueMetastoreService(glue_client)
            services.append(glue_service)
            logger.info(
                "m=get_active_services, runtime=databricks, "
                "msg=Glue enabled, registering in Spark + Glue"
            )
        else:
            logger.info(
                "m=get_active_services, runtime=databricks, "
                "msg=Glue not available, registering in Spark only"
            )
        return services

    @staticmethod
    def _add_uc_rest_service(
        services: List[MetastoreService],
    ) -> List[MetastoreService]:
        import importlib

        uc_rest_helper = importlib.import_module(
            "bietlejuice.base.spark.unity_catalog_rest_helper"
        ).UnityCatalogRestHelper

        if uc_rest_helper.is_uc_rest_enabled():
            from bietlejuice.services.metastore_services.unity_catalog_rest_metastore_service import (
                UnityCatalogRestMetastoreService,
            )

            uc_client = uc_rest_helper.get_uc_rest_client()
            uc_service = UnityCatalogRestMetastoreService(uc_client)
            services.append(uc_service)
            logger.info(
                "m=get_active_services, runtime=emr, "
                "msg=UC REST enabled, registering in Spark + UC"
            )
        else:
            logger.info(
                "m=get_active_services, runtime=emr, "
                "msg=UC REST not available, registering in Spark only"
            )
        return services
