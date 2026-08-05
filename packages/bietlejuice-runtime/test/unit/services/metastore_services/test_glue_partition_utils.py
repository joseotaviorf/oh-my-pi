"""Unit tests for Glue hive-style partition helpers."""

import unittest
from unittest.mock import MagicMock

from bietlejuice.services.metastore_services.glue_partition_utils import (
    build_hive_partition_path,
    build_partition_input,
    build_partition_update_entry,
    discover_hive_partitions_from_s3,
    format_partition_value,
    is_delta_glue_table,
    is_json_glue_table,
    merge_glue_columns,
    partition_serde_needs_update,
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


_HCATALOG = "org.apache.hive.hcatalog.data.JsonSerDe"
_OPENX = "org.openx.data.jsonserde.JsonSerDe"


def _hcatalog_sd(location="s3://bucket/raw/t/"):
    return {
        "Columns": [{"Name": "id", "Type": "bigint"}],
        "Location": location,
        "InputFormat": "org.apache.hadoop.mapred.TextInputFormat",
        "OutputFormat": "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat",
        "SerdeInfo": {
            "SerializationLibrary": _HCATALOG,
            "Parameters": {
                "serialization.format": "1",
                "timestamp.formats": "yyyy-MM-dd'T'HH:mm:ss'Z'",
            },
        },
    }


def _openx_sd(location="s3://bucket/raw/t/year=2020/month=01/day=01/"):
    return {
        "Columns": [{"Name": "id", "Type": "bigint"}],
        "Location": location,
        "InputFormat": "org.apache.hadoop.mapred.TextInputFormat",
        "OutputFormat": "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat",
        "SerdeInfo": {
            "SerializationLibrary": _OPENX,
            "Parameters": {"serialization.format": "1"},
        },
    }


class TestIsJsonGlueTable(unittest.TestCase):
    def test_classification_json(self):
        self.assertTrue(is_json_glue_table({"Parameters": {"classification": "json"}}))

    def test_hcatalog_serde(self):
        self.assertTrue(is_json_glue_table({"StorageDescriptor": _hcatalog_sd()}))

    def test_openx_serde(self):
        self.assertTrue(is_json_glue_table({"StorageDescriptor": _openx_sd()}))

    def test_parquet_not_json(self):
        self.assertFalse(
            is_json_glue_table(
                {
                    "Parameters": {"classification": "parquet"},
                    "StorageDescriptor": {
                        "SerdeInfo": {
                            "SerializationLibrary": (
                                "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
                            )
                        }
                    },
                }
            )
        )


class TestPartitionSerdeNeedsUpdate(unittest.TestCase):
    def test_openx_partition_needs_update(self):
        self.assertTrue(partition_serde_needs_update(_hcatalog_sd(), _openx_sd()))

    def test_matching_serde_no_update(self):
        part = _hcatalog_sd("s3://bucket/raw/t/year=2020/month=01/day=01/")
        self.assertFalse(partition_serde_needs_update(_hcatalog_sd(), part))

    def test_missing_timestamp_formats_needs_update(self):
        part = _hcatalog_sd("s3://bucket/raw/t/year=2020/month=01/day=01/")
        part["SerdeInfo"]["Parameters"] = {"serialization.format": "1"}
        self.assertTrue(partition_serde_needs_update(_hcatalog_sd(), part))


class TestBuildPartitionUpdateEntry(unittest.TestCase):
    def test_preserves_location_and_clones_table_serde(self):
        location = "s3://bucket/raw/t/year=2018/month=10/day=19/"
        partition = {
            "Values": ["2018", "10", "19"],
            "StorageDescriptor": _openx_sd(location),
            "Parameters": {"foo": "bar"},
        }
        entry = build_partition_update_entry(_hcatalog_sd(), partition)
        self.assertEqual(entry["PartitionValueList"], ["2018", "10", "19"])
        self.assertEqual(entry["PartitionInput"]["Values"], ["2018", "10", "19"])
        sd = entry["PartitionInput"]["StorageDescriptor"]
        self.assertEqual(sd["Location"], location)
        self.assertEqual(sd["SerdeInfo"]["SerializationLibrary"], _HCATALOG)
        self.assertIn("timestamp.formats", sd["SerdeInfo"]["Parameters"])
        self.assertEqual(entry["PartitionInput"]["Parameters"], {"foo": "bar"})


class TestMergeGlueColumns(unittest.TestCase):
    """A re-registration must never drop a column from the Glue table."""

    def test_narrower_incoming_schema_preserves_existing_column(self):
        existing = [
            {"Name": "id", "Type": "string"},
            {"Name": "origin_complement", "Type": "string"},
            {"Name": "amount_value", "Type": "double"},
        ]
        incoming = [
            {"Name": "id", "Type": "string"},
            {"Name": "amount_value", "Type": "double"},
        ]
        merged, preserved = merge_glue_columns(existing, incoming)
        self.assertEqual(
            [col["Name"] for col in merged],
            ["id", "origin_complement", "amount_value"],
        )
        self.assertEqual(preserved, ["origin_complement"])

    def test_new_column_appended_after_existing_ones(self):
        existing = [{"Name": "id", "Type": "string"}]
        incoming = [
            {"Name": "id", "Type": "string"},
            {"Name": "new_field", "Type": "string"},
        ]
        merged, preserved = merge_glue_columns(existing, incoming)
        self.assertEqual([col["Name"] for col in merged], ["id", "new_field"])
        self.assertEqual(preserved, [])

    def test_existing_order_is_stable(self):
        existing = [
            {"Name": "c", "Type": "string"},
            {"Name": "a", "Type": "string"},
            {"Name": "b", "Type": "string"},
        ]
        incoming = [
            {"Name": "a", "Type": "string"},
            {"Name": "b", "Type": "string"},
            {"Name": "c", "Type": "string"},
        ]
        merged, _ = merge_glue_columns(existing, incoming)
        self.assertEqual([col["Name"] for col in merged], ["c", "a", "b"])

    def test_type_collision_takes_incoming_type(self):
        merged, _ = merge_glue_columns(
            [{"Name": "amount_value", "Type": "string"}],
            [{"Name": "amount_value", "Type": "double"}],
        )
        self.assertEqual(merged, [{"Name": "amount_value", "Type": "double"}])

    def test_existing_column_metadata_survives_merge(self):
        merged, _ = merge_glue_columns(
            [{"Name": "id", "Type": "string", "Comment": "primary key"}],
            [{"Name": "id", "Type": "string"}],
        )
        self.assertEqual(merged[0]["Comment"], "primary key")

    def test_case_insensitive_match_keeps_registered_spelling(self):
        merged, preserved = merge_glue_columns(
            [{"Name": "date_event", "Type": "string"}],
            [{"Name": "DATE_EVENT", "Type": "timestamp"}],
        )
        self.assertEqual(merged, [{"Name": "date_event", "Type": "timestamp"}])
        self.assertEqual(preserved, [])

    def test_missing_or_empty_inputs(self):
        incoming = [{"Name": "id", "Type": "string"}]
        self.assertEqual(merge_glue_columns(None, incoming), (incoming, []))
        self.assertEqual(merge_glue_columns([], incoming), (incoming, []))
        self.assertEqual(merge_glue_columns(incoming, None), (incoming, ["id"]))
        self.assertEqual(merge_glue_columns(None, None), ([], []))

    def test_merged_columns_are_copies(self):
        existing = [{"Name": "id", "Type": "string"}]
        merged, _ = merge_glue_columns(existing, [])
        merged[0]["Type"] = "int"
        self.assertEqual(existing[0]["Type"], "string")
