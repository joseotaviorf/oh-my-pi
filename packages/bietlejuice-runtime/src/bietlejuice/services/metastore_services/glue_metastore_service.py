"""
MetastoreService implementation that registers table metadata in the
AWS Glue Data Catalog.

Core logic adapted from the ``GlueRegistrar`` in the UC-Glue sync script.
"""

from __future__ import annotations

from collections import OrderedDict
from typing import Dict, List

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.services.metastore_services.glue_partition_utils import (
    build_partition_input,
    discover_hive_partitions_from_s3,
    is_delta_glue_table,
    partition_tuples_to_dicts,
)
from bietlejuice.services.metastore_services.glue_storage_formats import (
    get_glue_format_config,
)
from bietlejuice.services.metastore_services.glue_type_mapper import (
    map_uc_type_to_glue,
)
from bietlejuice.services.metastore_services.metastore_service import (
    MetastoreService,
)

logger = QuintoAndarLogger("GlueMetastoreService")


class GlueMetastoreService(MetastoreService):
    """Service to register and manage table metadata in AWS Glue.

    :param glue_client: A ``GlueClient`` instance.
    """

    def __init__(self, glue_client):
        self._client = glue_client

    @property
    def client(self):
        return self._client

    # -- MetastoreService overrides ------------------------------------------

    def create_database(self, database_name: str) -> None:
        """Create a Glue database if it does not already exist."""
        self._client.ensure_database(
            database_name=database_name,
            description="Managed by bietlejuice — synced from Spark metastore",
        )
        logger.info(
            f"m=create_database, database_name={database_name}, "
            "msg=database ensured in Glue"
        )

    def create_external_table(
        self,
        database_name: str,
        table_name: str,
        table_location: str,
        table_schema: OrderedDict,
        partition_cols: list,
        format_options,
    ) -> None:
        """Create or update an external table in the Glue Data Catalog.

        :param database_name: Glue database name (same as Spark database).
        :param table_name: Table name.
        :param table_location: S3 location of the underlying data.
        :param table_schema: ``OrderedDict`` of ``{col_name: col_type}``.
        :param partition_cols: List of partition column names, or list of
            ``(col_name, col_type)`` tuples.
        :param format_options: Table format string (e.g. ``"PARQUET"``,
            ``"JSON"``, ``"DELTA"``).  When a ``dict`` is passed (legacy
            Hive format info), falls back to ``"PARQUET"``.
        """
        format_str = self._resolve_format(format_options)
        table_input = self._build_table_input(
            table_name=table_name,
            table_location=table_location,
            table_schema=table_schema,
            partition_cols=partition_cols,
            format_str=format_str,
        )

        existing = self._client.get_table(database_name, table_name)
        if existing:
            logger.info(
                f"m=create_external_table, table={database_name}.{table_name}, "
                "msg=table exists in Glue, updating"
            )
            self._client.update_table(database_name, table_input)
        else:
            logger.info(
                f"m=create_external_table, table={database_name}.{table_name}, "
                "msg=creating table in Glue"
            )
            self._client.create_table(database_name, table_input)

    def drop_table(self, database_name: str, table_name: str) -> None:
        self._client.delete_table(database_name, table_name)

    def get_table_names(self, database_name: str, regex: str = "*") -> List[str]:
        return self._client.get_table_names(database_name)

    def repair_table_partitions(self, database_name: str, table_name: str) -> None:
        """Register S3 hive-style partitions missing from the Glue catalog."""
        table = self._client.get_table(database_name, table_name)
        if not table:
            logger.warning(
                f"m=repair_table_partitions, table={database_name}.{table_name}, "
                "msg=table not found in Glue, skipping"
            )
            return

        if is_delta_glue_table(table):
            logger.info(
                f"m=repair_table_partitions, table={database_name}.{table_name}, "
                "msg=Delta table, Glue partition repair not required, skipping"
            )
            return

        partition_key_names = [
            pk["Name"] for pk in table.get("PartitionKeys", []) if pk.get("Name")
        ]
        if not partition_key_names:
            logger.info(
                f"m=repair_table_partitions, table={database_name}.{table_name}, "
                "msg=table is not partitioned, skipping"
            )
            return

        table_sd = table.get("StorageDescriptor")
        if not table_sd or not table_sd.get("Location"):
            logger.info(
                f"m=repair_table_partitions, table={database_name}.{table_name}, "
                "msg=table lacks StorageDescriptor or Location (e.g. a view), skipping"
            )
            return

        table_location = table_sd["Location"]
        discovered = discover_hive_partitions_from_s3(
            table_location, partition_key_names, s3_client=self._client.s3_client
        )
        if not discovered:
            logger.info(
                f"m=repair_table_partitions, table={database_name}.{table_name}, "
                "msg=no hive-style partitions discovered on S3, skipping"
            )
            return

        existing = self._client.get_partition_value_tuples(database_name, table_name)
        missing_tuples = [values for values in discovered if values not in existing]
        if not missing_tuples:
            logger.info(
                f"m=repair_table_partitions, table={database_name}.{table_name}, "
                "msg=all discovered partitions already registered in Glue"
            )
            return

        partition_dicts = partition_tuples_to_dicts(partition_key_names, missing_tuples)
        logger.info(
            f"m=repair_table_partitions, table={database_name}.{table_name}, "
            f"partition_count={len(partition_dicts)}, "
            "msg=registering missing partitions in Glue"
        )
        self.add_partitions(database_name, table_name, partition_dicts)

    def create_new_partitions_from_df(
        self, database_name, table_name, df, partition_cols, parallelism=1
    ):
        """Register every distinct partition found in ``df`` in a single batch.

        Overrides the base implementation, which calls ``add_partitions`` once per
        distinct partition (one ``get_table`` boto3 call each). Collecting all
        partition dicts up front means a single ``get_table`` plus the batched
        ``batch_create_partition``, which avoids hammering Glue (and getting
        throttled — secondary-catalog failures are swallowed by the composite, so a
        throttled partition would be silently dropped).
        """
        distinct_rows = df.select(partition_cols).distinct().rdd.map(tuple).collect()
        partition_dicts = [dict(zip(partition_cols, row)) for row in distinct_rows]
        self.add_partitions(database_name, table_name, partition_dicts)

    def add_partitions(self, database_name, table_name, partitions):
        """Register hive-style partitions in Glue via ``batch_create_partition``."""
        if not partitions:
            return

        table = self._client.get_table(database_name, table_name)
        if not table:
            logger.warning(
                f"m=add_partitions, table={database_name}.{table_name}, "
                "msg=table not found in Glue, skipping partition registration"
            )
            return

        if is_delta_glue_table(table):
            logger.info(
                f"m=add_partitions, table={database_name}.{table_name}, "
                "msg=Delta table, skipping Glue partition registration"
            )
            return

        partition_key_names = [
            pk["Name"] for pk in table.get("PartitionKeys", []) if pk.get("Name")
        ]
        if not partition_key_names:
            logger.warning(
                f"m=add_partitions, table={database_name}.{table_name}, "
                "msg=table has no partition keys in Glue, skipping"
            )
            return

        table_sd = table.get("StorageDescriptor")
        if not table_sd or not table_sd.get("Location"):
            logger.info(
                f"m=add_partitions, table={database_name}.{table_name}, "
                "msg=table lacks StorageDescriptor or Location (e.g. a view), skipping"
            )
            return

        table_location = table_sd["Location"]

        # No existence pre-check: do NOT scan the table's partition list
        # (``get_partition_value_tuples``) nor point-look-up each partition
        # (``get_partition``). ``batch_create_partition`` is idempotent, so we just
        # submit the supplied partitions. Hot-path cost stays O(N) in the partitions
        # of this write, never O(total partitions in the table).
        partition_inputs: List[Dict] = []
        for partition in partitions:
            missing_keys = [key for key in partition_key_names if key not in partition]
            if missing_keys:
                logger.warning(
                    f"m=add_partitions, table={database_name}.{table_name}, "
                    f"missing_keys={missing_keys}, msg=partition dict incomplete, skipping"
                )
                continue

            partition_inputs.append(
                build_partition_input(
                    table_sd, partition_key_names, partition, table_location
                )
            )

        if not partition_inputs:
            logger.info(
                f"m=add_partitions, table={database_name}.{table_name}, "
                "msg=no new partitions to register in Glue"
            )
            return

        created_count = self._client.batch_create_partition(
            database_name, table_name, partition_inputs
        )
        logger.info(
            f"m=add_partitions, table={database_name}.{table_name}, "
            f"partition_count={len(partition_inputs)}, "
            f"created_count={created_count}, "
            "msg=partitions registered in Glue"
        )

    # -- Internal helpers ----------------------------------------------------

    @staticmethod
    def _resolve_format(format_options) -> str:
        """Normalise ``format_options`` to an upper-case format string."""
        if isinstance(format_options, str):
            return format_options.upper()
        if isinstance(format_options, dict):
            return format_options.get("format", "PARQUET").upper()
        return "PARQUET"

    @staticmethod
    def _build_table_input(
        table_name: str,
        table_location: str,
        table_schema: OrderedDict,
        partition_cols: list,
        format_str: str,
    ) -> Dict:
        """Build the ``TableInput`` dict expected by the Glue API.

        Delta tables use Hive stub SerDe + Spark table properties so Glue
        matches the shape Spark recognizes for external Delta tables.
        """
        fmt = get_glue_format_config(format_str)

        regular_columns, partition_columns = GlueMetastoreService._split_columns(
            table_schema, partition_cols
        )

        norm_loc = GlueMetastoreService._normalise_location(table_location)

        params: Dict[str, str] = {
            "classification": fmt.classification,
        }
        params.update(fmt.table_params)

        serde_params = dict(fmt.serde_params)
        if format_str.upper() == "DELTA":
            serde_params["path"] = norm_loc

        table_input: Dict = {
            "Name": table_name,
            "StorageDescriptor": {
                "Columns": GlueMetastoreService._build_glue_columns(regular_columns),
                "Location": norm_loc,
                "InputFormat": fmt.input_format,
                "OutputFormat": fmt.output_format,
                "SerdeInfo": {
                    "SerializationLibrary": fmt.serialization_library,
                    "Parameters": serde_params,
                },
                "Compressed": False,
                "StoredAsSubDirectories": False,
            },
            "PartitionKeys": GlueMetastoreService._build_glue_columns(
                partition_columns
            ),
            "TableType": "EXTERNAL_TABLE",
            "Parameters": params,
        }
        return table_input

    @staticmethod
    def _split_columns(table_schema: OrderedDict, partition_cols: list) -> tuple:
        """Separate regular columns from partition columns.

        ``partition_cols`` may be a list of strings (column names) or a
        list of ``(name, type)`` tuples.
        """
        if not partition_cols:
            return list(table_schema.items()), []

        partition_names = set()
        partition_typed: List[tuple] = []

        for item in partition_cols:
            if isinstance(item, (list, tuple)) and len(item) == 2:
                partition_names.add(item[0])
                partition_typed.append((item[0], item[1]))
            else:
                partition_names.add(str(item))

        regular = [
            (col, col_type)
            for col, col_type in table_schema.items()
            if col not in partition_names
        ]

        if not partition_typed:
            partition_typed = [
                (col, table_schema.get(col, "string"))
                for col in partition_cols
                if isinstance(col, str)
            ]

        return regular, partition_typed

    @staticmethod
    def _build_glue_columns(columns: list) -> List[Dict]:
        """Convert a list of ``(name, type)`` tuples to Glue column dicts."""
        result: List[Dict] = []
        for col_name, col_type in columns:
            result.append({"Name": col_name, "Type": map_uc_type_to_glue(col_type)})
        return result

    @staticmethod
    def _normalise_location(location: str) -> str:
        """Ensure the S3 location uses the ``s3://`` scheme."""
        if location.startswith("s3a://"):
            return location.replace("s3a://", "s3://", 1)
        if location.startswith("s3n://"):
            return location.replace("s3n://", "s3://", 1)
        return location
