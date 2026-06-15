"""Unit tests for GlueMetastoreService partition registration."""

import unittest
from unittest.mock import MagicMock

from bietlejuice.services.metastore_services.glue_metastore_service import (
    GlueMetastoreService,
)


def _parquet_glue_table():
    return {
        "Name": "events",
        "StorageDescriptor": {
            "Columns": [{"Name": "id", "Type": "bigint"}],
            "Location": "s3://bucket/raw/source/events/",
            "InputFormat": "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat",
            "OutputFormat": "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat",
            "SerdeInfo": {
                "SerializationLibrary": "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe",
                "Parameters": {"serialization.format": "1"},
            },
        },
        "PartitionKeys": [
            {"Name": "year", "Type": "string"},
            {"Name": "month", "Type": "string"},
            {"Name": "day", "Type": "string"},
        ],
        "Parameters": {"classification": "parquet"},
    }


class TestGlueMetastoreServicePartitions(unittest.TestCase):
    def setUp(self):
        self.glue_client = MagicMock()
        self.service = GlueMetastoreService(self.glue_client)

    def test_add_partitions_registers_new_day_partition(self):
        self.glue_client.get_table.return_value = _parquet_glue_table()
        self.glue_client.get_partition.return_value = None

        self.service.add_partitions(
            "raw_source",
            "events",
            [{"year": "2026", "month": "06", "day": "12"}],
        )

        self.glue_client.batch_create_partition.assert_called_once()
        database_name, table_name, partition_inputs = (
            self.glue_client.batch_create_partition.call_args.args
        )
        self.assertEqual(database_name, "raw_source")
        self.assertEqual(table_name, "events")
        self.assertEqual(len(partition_inputs), 1)
        self.assertEqual(partition_inputs[0]["Values"], ["2026", "06", "12"])
        self.assertEqual(
            partition_inputs[0]["StorageDescriptor"]["Location"],
            "s3://bucket/raw/source/events/year=2026/month=06/day=12/",
        )

    def test_add_partitions_does_not_scan_partitions_on_write_path(self):
        """Hot path must never list/point-lookup partitions: O(N) in this write only.

        Existing partitions are handled idempotently by ``batch_create_partition``,
        not by a pre-check that would scan the whole table.
        """
        self.glue_client.get_table.return_value = _parquet_glue_table()

        self.service.add_partitions(
            "raw_source",
            "events",
            [{"year": "2026", "month": "06", "day": "12"}],
        )

        # No full partition-list scan and no per-partition point lookup.
        self.glue_client.get_partition_value_tuples.assert_not_called()
        self.glue_client.get_partition.assert_not_called()
        # The partition is still submitted; Glue dedups it idempotently.
        self.glue_client.batch_create_partition.assert_called_once()

    def test_create_new_partitions_from_df_uses_single_batch(self):
        """All distinct df partitions go through one get_table + one batch call."""
        self.glue_client.get_table.return_value = _parquet_glue_table()

        df = MagicMock()
        df.select.return_value.distinct.return_value.rdd.map.return_value.collect.return_value = [
            ("2026", "06", "11"),
            ("2026", "06", "12"),
        ]

        self.service.create_new_partitions_from_df(
            "raw_source", "events", df, ["year", "month", "day"]
        )

        self.glue_client.get_table.assert_called_once()
        self.glue_client.batch_create_partition.assert_called_once()
        _, _, partition_inputs = self.glue_client.batch_create_partition.call_args.args
        self.assertEqual(len(partition_inputs), 2)
        self.assertEqual(partition_inputs[0]["Values"], ["2026", "06", "11"])
        self.assertEqual(partition_inputs[1]["Values"], ["2026", "06", "12"])

    def test_add_partitions_skips_table_without_storage_descriptor(self):
        # A partitioned Glue view has PartitionKeys but no StorageDescriptor;
        # it must be skipped rather than raising KeyError.
        view = {
            "Name": "events_view",
            "PartitionKeys": [{"Name": "year", "Type": "string"}],
            "Parameters": {"classification": "parquet"},
        }
        self.glue_client.get_table.return_value = view

        self.service.add_partitions("raw_source", "events_view", [{"year": "2026"}])

        self.glue_client.batch_create_partition.assert_not_called()

    def test_repair_table_partitions_skips_table_without_storage_descriptor(self):
        view = {
            "Name": "events_view",
            "PartitionKeys": [{"Name": "year", "Type": "string"}],
            "Parameters": {"classification": "parquet"},
        }
        self.glue_client.get_table.return_value = view

        # Must not raise and must not attempt any registration.
        self.service.repair_table_partitions("raw_source", "events_view")

        self.glue_client.batch_create_partition.assert_not_called()

    def test_add_partitions_skips_delta_tables(self):
        self.glue_client.get_table.return_value = {
            **_parquet_glue_table(),
            "Parameters": {"spark.sql.sources.provider": "delta"},
        }

        self.service.add_partitions(
            "raw_source",
            "events",
            [{"year": "2026", "month": "06", "day": "12"}],
        )

        self.glue_client.batch_create_partition.assert_not_called()

    def test_repair_table_partitions_registers_missing_s3_partitions(self):
        self.glue_client.get_table.return_value = _parquet_glue_table()
        self.glue_client.get_partition_value_tuples.return_value = {
            ("2026", "06", "11"),
        }

        s3_client = MagicMock()
        paginator = MagicMock()
        s3_client.get_paginator.return_value = paginator
        paginator.paginate.side_effect = [
            [{"CommonPrefixes": [{"Prefix": "raw/source/events/year=2026/"}]}],
            [{"CommonPrefixes": [{"Prefix": "raw/source/events/year=2026/month=06/"}]}],
            [
                {
                    "CommonPrefixes": [
                        {"Prefix": "raw/source/events/year=2026/month=06/day=11/"},
                        {"Prefix": "raw/source/events/year=2026/month=06/day=12/"},
                    ]
                }
            ],
        ]

        with unittest.mock.patch(
            "bietlejuice.services.metastore_services.glue_metastore_service.discover_hive_partitions_from_s3",
            return_value=[("2026", "06", "11"), ("2026", "06", "12")],
        ):
            self.glue_client.get_partition.side_effect = lambda _db, _tbl, values: (
                {"Values": values} if values == ["2026", "06", "11"] else None
            )
            self.service.repair_table_partitions("raw_source", "events")

        self.glue_client.batch_create_partition.assert_called_once()
        _, _, partition_inputs = self.glue_client.batch_create_partition.call_args.args
        self.assertEqual(len(partition_inputs), 1)
        self.assertEqual(partition_inputs[0]["Values"], ["2026", "06", "12"])
