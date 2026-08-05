"""Unit tests for GlueMetastoreService.sync_json_partition_serde."""

import unittest
from unittest.mock import MagicMock

from bietlejuice.services.metastore_services.glue_metastore_service import (
    GlueMetastoreService,
)

_HCATALOG = "org.apache.hive.hcatalog.data.JsonSerDe"
_OPENX = "org.openx.data.jsonserde.JsonSerDe"


def _json_table(*, openx_table: bool = False):
    serde = _OPENX if openx_table else _HCATALOG
    params = {"serialization.format": "1"}
    if not openx_table:
        params["timestamp.formats"] = "yyyy-MM-dd'T'HH:mm:ss'Z'"
    return {
        "Name": "report_card",
        "StorageDescriptor": {
            "Columns": [{"Name": "id", "Type": "bigint"}],
            "Location": "s3://bucket/raw/metabase/report_card/",
            "InputFormat": "org.apache.hadoop.mapred.TextInputFormat",
            "OutputFormat": "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat",
            "SerdeInfo": {
                "SerializationLibrary": serde,
                "Parameters": params,
            },
        },
        "PartitionKeys": [
            {"Name": "year", "Type": "string"},
            {"Name": "month", "Type": "string"},
            {"Name": "day", "Type": "string"},
        ],
        "Parameters": {"classification": "json"},
    }


def _partition(values, *, openx: bool = True):
    location = (
        f"s3://bucket/raw/metabase/report_card/"
        f"year={values[0]}/month={values[1]}/day={values[2]}/"
    )
    serde = _OPENX if openx else _HCATALOG
    params = {"serialization.format": "1"}
    if not openx:
        params["timestamp.formats"] = "yyyy-MM-dd'T'HH:mm:ss'Z'"
    return {
        "Values": list(values),
        "StorageDescriptor": {
            "Columns": [{"Name": "id", "Type": "bigint"}],
            "Location": location,
            "InputFormat": "org.apache.hadoop.mapred.TextInputFormat",
            "OutputFormat": "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat",
            "SerdeInfo": {
                "SerializationLibrary": serde,
                "Parameters": params,
            },
        },
        "Parameters": {},
    }


class TestSyncJsonPartitionSerde(unittest.TestCase):
    def setUp(self):
        self.glue_client = MagicMock()
        self.service = GlueMetastoreService(self.glue_client)

    def test_updates_stale_openx_partitions(self):
        self.glue_client.get_table.return_value = _json_table()
        self.glue_client.get_partitions.return_value = [
            _partition(["2018", "10", "19"], openx=True),
            _partition(["2024", "01", "01"], openx=False),
        ]
        self.glue_client.batch_update_partition.return_value = 1

        result = self.service.sync_json_partition_serde(
            "datalake_metabase_raw", "report_card"
        )

        self.assertEqual(result["scanned"], 2)
        self.assertEqual(result["updated"], 1)
        self.glue_client.batch_update_partition.assert_called_once()
        db, table, entries = self.glue_client.batch_update_partition.call_args.args
        self.assertEqual(db, "datalake_metabase_raw")
        self.assertEqual(table, "report_card")
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["PartitionValueList"], ["2018", "10", "19"])
        sd = entries[0]["PartitionInput"]["StorageDescriptor"]
        self.assertEqual(sd["SerdeInfo"]["SerializationLibrary"], _HCATALOG)
        self.assertEqual(
            sd["Location"],
            "s3://bucket/raw/metabase/report_card/year=2018/month=10/day=19/",
        )

    def test_dry_run_does_not_call_update(self):
        self.glue_client.get_table.return_value = _json_table()
        self.glue_client.get_partitions.return_value = [
            _partition(["2018", "10", "19"], openx=True),
        ]

        result = self.service.sync_json_partition_serde(
            "datalake_metabase_raw", "report_card", dry_run=True
        )

        self.assertEqual(result["updated"], 1)
        self.glue_client.batch_update_partition.assert_not_called()

    def test_pushes_openx_table_serde_onto_hcatalog_partitions(self):
        """The revert direction: table is OpenX again, partitions still HCatalog.

        The sync is direction-agnostic — whatever the table carries becomes the
        target — so this is the mode the SerDe backfill actually runs in.
        """
        self.glue_client.get_table.return_value = _json_table(openx_table=True)
        self.glue_client.get_partitions.return_value = [
            _partition(["2018", "10", "19"], openx=False),
            _partition(["2024", "01", "01"], openx=True),
        ]
        self.glue_client.batch_update_partition.return_value = 1

        result = self.service.sync_json_partition_serde(
            "datalake_metabase_raw", "report_card"
        )

        self.assertEqual(result["scanned"], 2)
        self.assertEqual(result["updated"], 1)
        self.glue_client.batch_update_partition.assert_called_once()
        _, _, entries = self.glue_client.batch_update_partition.call_args.args
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["PartitionValueList"], ["2018", "10", "19"])
        sd = entries[0]["PartitionInput"]["StorageDescriptor"]
        self.assertEqual(sd["SerdeInfo"]["SerializationLibrary"], _OPENX)
        self.assertNotIn("timestamp.formats", sd["SerdeInfo"]["Parameters"])

    def test_skips_delta_table(self):
        self.glue_client.get_table.return_value = {
            "Name": "events",
            "Parameters": {"spark.sql.sources.provider": "delta"},
            "PartitionKeys": [{"Name": "year", "Type": "string"}],
            "StorageDescriptor": {"Location": "s3://bucket/t/"},
        }

        result = self.service.sync_json_partition_serde("db", "events")

        self.assertEqual(result["skipped"], 1)
        self.glue_client.get_partitions.assert_not_called()

    def test_skips_non_json_table(self):
        self.glue_client.get_table.return_value = {
            "Name": "events",
            "Parameters": {"classification": "parquet"},
            "PartitionKeys": [{"Name": "year", "Type": "string"}],
            "StorageDescriptor": {
                "Location": "s3://bucket/t/",
                "SerdeInfo": {
                    "SerializationLibrary": (
                        "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
                    ),
                    "Parameters": {},
                },
            },
        }

        result = self.service.sync_json_partition_serde("db", "events")

        self.assertEqual(result["skipped"], 1)
        self.glue_client.get_partitions.assert_not_called()

    def test_no_op_when_all_partitions_match(self):
        self.glue_client.get_table.return_value = _json_table()
        self.glue_client.get_partitions.return_value = [
            _partition(["2024", "01", "01"], openx=False),
        ]

        result = self.service.sync_json_partition_serde(
            "datalake_metabase_raw", "report_card"
        )

        self.assertEqual(result["scanned"], 1)
        self.assertEqual(result["updated"], 0)
        self.glue_client.batch_update_partition.assert_not_called()
