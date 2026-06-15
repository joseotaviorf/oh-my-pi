"""Unit tests for Glue hive-style partition helpers."""

import unittest
from unittest.mock import MagicMock

from bietlejuice.services.metastore_services.glue_partition_utils import (
    build_hive_partition_path,
    build_partition_input,
    discover_hive_partitions_from_s3,
    format_partition_value,
    is_delta_glue_table,
    partition_tuples_to_dicts,
    partition_values_tuple,
)


class TestFormatPartitionValue(unittest.TestCase):
    def test_int_coerced_to_string(self):
        self.assertEqual(format_partition_value(12), "12")

    def test_string_preserved(self):
        self.assertEqual(format_partition_value("06"), "06")


class TestBuildHivePartitionPath(unittest.TestCase):
    def test_builds_nested_hive_path(self):
        path = build_hive_partition_path(
            "s3a://bucket/raw/source/table",
            ["year", "month", "day"],
            {"year": 2026, "month": "06", "day": 12},
        )
        self.assertEqual(
            path,
            "s3://bucket/raw/source/table/year=2026/month=06/day=12/",
        )


class TestBuildPartitionInput(unittest.TestCase):
    def test_parquet_partition_input_shape(self):
        table_sd = {
            "Columns": [{"Name": "id", "Type": "bigint"}],
            "Location": "s3://bucket/raw/source/table/",
            "InputFormat": "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat",
            "OutputFormat": "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat",
            "SerdeInfo": {
                "SerializationLibrary": "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe",
                "Parameters": {"serialization.format": "1"},
            },
        }
        partition_input = build_partition_input(
            table_sd,
            ["year", "month", "day"],
            {"year": "2026", "month": "06", "day": "12"},
            "s3://bucket/raw/source/table/",
        )
        self.assertEqual(partition_input["Values"], ["2026", "06", "12"])
        self.assertEqual(
            partition_input["StorageDescriptor"]["Location"],
            "s3://bucket/raw/source/table/year=2026/month=06/day=12/",
        )
        self.assertEqual(
            partition_input["StorageDescriptor"]["InputFormat"],
            table_sd["InputFormat"],
        )


class TestIsDeltaGlueTable(unittest.TestCase):
    def test_delta_by_provider(self):
        self.assertTrue(
            is_delta_glue_table({"Parameters": {"spark.sql.sources.provider": "delta"}})
        )

    def test_parquet_is_not_delta(self):
        self.assertFalse(
            is_delta_glue_table({"Parameters": {"classification": "parquet"}})
        )


class TestDiscoverHivePartitionsFromS3(unittest.TestCase):
    def test_discovers_year_month_day_prefixes(self):
        s3_client = MagicMock()
        paginator = MagicMock()
        s3_client.get_paginator.return_value = paginator
        paginator.paginate.side_effect = [
            [{"CommonPrefixes": [{"Prefix": "raw/table/year=2026/"}]}],
            [{"CommonPrefixes": [{"Prefix": "raw/table/year=2026/month=06/"}]}],
            [
                {
                    "CommonPrefixes": [
                        {"Prefix": "raw/table/year=2026/month=06/day=11/"},
                        {"Prefix": "raw/table/year=2026/month=06/day=12/"},
                    ]
                }
            ],
        ]

        discovered = discover_hive_partitions_from_s3(
            "s3://bucket/raw/table/",
            ["year", "month", "day"],
            s3_client=s3_client,
        )

        self.assertEqual(
            discovered,
            [("2026", "06", "11"), ("2026", "06", "12")],
        )


class TestPartitionTuplesToDicts(unittest.TestCase):
    def test_converts_tuples(self):
        result = partition_tuples_to_dicts(
            ["year", "month", "day"],
            [("2026", "06", "12")],
        )
        self.assertEqual(
            result,
            [{"year": "2026", "month": "06", "day": "12"}],
        )


class TestPartitionValuesTuple(unittest.TestCase):
    def test_respects_key_order(self):
        values = partition_values_tuple(
            ["year", "month", "day"],
            {"day": 12, "month": "06", "year": 2026},
        )
        self.assertEqual(values, ("2026", "06", "12"))
