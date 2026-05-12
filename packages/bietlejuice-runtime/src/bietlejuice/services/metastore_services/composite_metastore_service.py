"""
Composite MetastoreService that delegates every operation to multiple
underlying ``MetastoreService`` instances.

This enables registering tables in both Databricks (Spark/UC) and AWS
Glue in a single call, without scattering if/else logic across pipelines.
"""

from __future__ import annotations

from typing import List

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.services.metastore_services.metastore_service import (
    MetastoreService,
)

logger = QuintoAndarLogger("CompositeMetastoreService")


class CompositeMetastoreService(MetastoreService):
    """Fan-out wrapper that delegates to one or more ``MetastoreService``
    implementations.

    The **first** service in the list is considered the *primary* and is
    used for read operations (``get_table_names``, ``get_table_description``).
    Write operations are dispatched to **all** services; failures in
    secondary services are logged but do not abort the pipeline.

    :param services: Ordered list of ``MetastoreService`` instances.
        The first element is the primary.
    """

    def __init__(self, services: List[MetastoreService]):
        if not services:
            raise ValueError("CompositeMetastoreService requires at least one service")
        self._services = services
        self._primary = services[0]

    @property
    def client(self):
        return self._primary.client

    # -- Write operations (fan-out to all) -----------------------------------

    def create_database(self, database_name: str) -> None:
        for svc in self._services:
            try:
                svc.create_database(database_name)
            except Exception as exc:
                if svc is self._primary:
                    raise
                logger.warning(
                    f"m=create_database, service={type(svc).__name__}, "
                    f"database={database_name}, error={exc}, "
                    "msg=secondary service failed, continuing"
                )

    def create_external_table(
        self,
        database_name,
        table_name,
        table_location,
        table_schema,
        partition_cols,
        format_options,
    ) -> None:
        for svc in self._services:
            try:
                svc.create_external_table(
                    database_name,
                    table_name,
                    table_location,
                    table_schema,
                    partition_cols,
                    format_options,
                )
            except Exception as exc:
                if svc is self._primary:
                    raise
                logger.warning(
                    f"m=create_external_table, service={type(svc).__name__}, "
                    f"table={database_name}.{table_name}, error={exc}, "
                    "msg=secondary service failed, continuing"
                )

    def drop_table(self, database_name: str, table_name: str) -> None:
        for svc in self._services:
            try:
                svc.drop_table(database_name, table_name)
            except Exception as exc:
                if svc is self._primary:
                    raise
                logger.warning(
                    f"m=drop_table, service={type(svc).__name__}, "
                    f"table={database_name}.{table_name}, error={exc}, "
                    "msg=secondary service failed, continuing"
                )

    def repair_table_partitions(self, database_name: str, table_name: str) -> None:
        for svc in self._services:
            try:
                svc.repair_table_partitions(database_name, table_name)
            except Exception as exc:
                if svc is self._primary:
                    raise
                logger.warning(
                    f"m=repair_table_partitions, service={type(svc).__name__}, "
                    f"table={database_name}.{table_name}, error={exc}, "
                    "msg=secondary service failed, continuing"
                )

    def add_partitions(self, database_name, table_name, partitions) -> None:
        for svc in self._services:
            try:
                svc.add_partitions(database_name, table_name, partitions)
            except Exception as exc:
                if svc is self._primary:
                    raise
                logger.warning(
                    f"m=add_partitions, service={type(svc).__name__}, "
                    f"table={database_name}.{table_name}, error={exc}, "
                    "msg=secondary service failed, continuing"
                )

    def create_new_partitions_from_df(
        self, database_name, table_name, df, partition_cols, parallelism=1
    ) -> None:
        for svc in self._services:
            try:
                svc.create_new_partitions_from_df(
                    database_name, table_name, df, partition_cols, parallelism
                )
            except Exception as exc:
                if svc is self._primary:
                    raise
                logger.warning(
                    f"m=create_new_partitions_from_df, "
                    f"service={type(svc).__name__}, "
                    f"table={database_name}.{table_name}, error={exc}, "
                    "msg=secondary service failed, continuing"
                )

    # -- Read operations (primary only) --------------------------------------

    def get_table_names(self, database_name: str, regex: str = "*"):
        return self._primary.get_table_names(database_name, regex)

    def get_table_description(
        self, database_name: str, table_name: str, formatted: bool = False
    ):
        return self._primary.get_table_description(database_name, table_name, formatted)

    # -- SparkMetastoreService-only (primary delegation) ---------------------

    def _spark_primary(self):
        from bietlejuice.services.metastore_services.spark_metastore_service import (
            SparkMetastoreService,
        )

        if not isinstance(self._primary, SparkMetastoreService):
            raise TypeError(
                "CompositeMetastoreService primary must be SparkMetastoreService, "
                f"got {type(self._primary).__name__}"
            )
        return self._primary

    def refresh_table(self, database_name: str, table_name: str) -> None:
        return self._spark_primary().refresh_table(database_name, table_name)

    def get_table_schema(self, database_name, table_name, ignore_partition_keys=False):
        return self._spark_primary().get_table_schema(
            database_name, table_name, ignore_partition_keys
        )

    def merge_table_and_dataframe_schemas(self, database_name, table_name, df):
        return self._spark_primary().merge_table_and_dataframe_schemas(
            database_name, table_name, df
        )
