"""Unit tests for GlueMetastoreService Glue TableInput shape (Delta)."""

import os
import subprocess
import sys
import unittest
from collections import OrderedDict
from pathlib import Path

from bietlejuice.services.metastore_services.glue_metastore_service import (
    GlueMetastoreService,
)

_REPO_ROOT = Path(__file__).resolve().parents[4]


class TestGlueMetastoreServiceTableInput(unittest.TestCase):
    """Assert Delta tables use Hive stub SerDe + Spark table properties."""

    def test_fresh_import_does_not_load_base_spark(self):
        """Workers unpickle closures that touch metastore code; must not init SparkContext."""
        env = os.environ.copy()
        env["PYTHONPATH"] = str(_REPO_ROOT)
        code = (
            "import sys; "
            "import bietlejuice.services.metastore_services.glue_metastore_service; "
            "bad = [k for k in sys.modules if k.startswith('bietlejuice.base.spark')]; "
            "sys.exit(1 if bad else 0)"
        )
        proc = subprocess.run(
            [sys.executable, "-c", code],
            cwd=str(_REPO_ROOT),
            env=env,
            capture_output=True,
            text=True,
            timeout=60,
        )
        self.assertEqual(
            proc.returncode,
            0,
            msg=(proc.stdout or "") + (proc.stderr or ""),
        )

    def test_delta_uses_hive_stub_serde_and_spark_table_params(self):
        schema = OrderedDict([("id", "bigint"), ("x", "string")])
        ti = GlueMetastoreService._build_table_input(
            table_name="t1",
            table_location="s3://bucket/prefix/t1",
            table_schema=schema,
            partition_cols=[],
            format_str="DELTA",
        )
        sd = ti["StorageDescriptor"]
        self.assertEqual(
            sd["InputFormat"],
            "org.apache.hadoop.mapred.SequenceFileInputFormat",
        )
        self.assertIn("HiveSequenceFileOutputFormat", sd["OutputFormat"])
        self.assertEqual(
            sd["SerdeInfo"]["SerializationLibrary"],
            "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe",
        )
        sparams = sd["SerdeInfo"]["Parameters"]
        self.assertEqual(sparams.get("serialization.format"), "1")
        self.assertEqual(sparams.get("path"), "s3://bucket/prefix/t1")

        params = ti["Parameters"]
        self.assertEqual(params.get("classification"), "delta")
        self.assertEqual(params.get("spark.sql.sources.provider"), "delta")
        self.assertEqual(
            params.get("spark.sql.sources.schema"),
            '{"type":"struct","fields":[]}',
        )
        self.assertEqual(params.get("spark.sql.partitionProvider"), "catalog")
        self.assertEqual(params.get("EXTERNAL"), "TRUE")
        self.assertNotIn("unity_catalog_source", params)

    def test_json_uses_hive_json_serde_with_iso_timestamp_formats(self):
        """Databricks→Glue secondary sync must not use OpenX (rejects ISO T/Z)."""
        schema = OrderedDict(
            [("id", "bigint"), ("created_at", "timestamp"), ("year", "int")]
        )
        ti = GlueMetastoreService._build_table_input(
            table_name="report_card",
            table_location="s3://bucket/raw/report_card",
            table_schema=schema,
            partition_cols=["year"],
            format_str="JSON",
        )
        sd = ti["StorageDescriptor"]
        self.assertEqual(
            sd["SerdeInfo"]["SerializationLibrary"],
            "org.apache.hive.hcatalog.data.JsonSerDe",
        )
        sparams = sd["SerdeInfo"]["Parameters"]
        self.assertIn("timestamp.formats", sparams)
        self.assertIn("'T'", sparams["timestamp.formats"])
        self.assertIn("'Z'", sparams["timestamp.formats"])
        self.assertEqual(ti["Parameters"].get("classification"), "json")
        self.assertNotIn("openx", sd["SerdeInfo"]["SerializationLibrary"].lower())

    def test_update_preserves_unity_catalog_source(self):
        """Databricks secondary Glue tables carry UC provenance; keep it on update."""
        from unittest.mock import MagicMock

        glue_client = MagicMock()
        glue_client.get_table.return_value = {
            "Name": "report_card",
            "Parameters": {
                "classification": "json",
                "unity_catalog_source": (
                    "quintoandar_prod.datalake_metabase_raw.report_card"
                ),
            },
        }
        svc = GlueMetastoreService(glue_client)
        schema = OrderedDict([("id", "bigint"), ("created_at", "timestamp")])
        svc.create_external_table(
            database_name="datalake_metabase_raw",
            table_name="report_card",
            table_location="s3://bucket/raw/report_card",
            table_schema=schema,
            partition_cols=[],
            format_options="JSON",
        )
        glue_client.update_table.assert_called_once()
        table_input = glue_client.update_table.call_args[0][1]
        self.assertEqual(
            table_input["Parameters"]["unity_catalog_source"],
            "quintoandar_prod.datalake_metabase_raw.report_card",
        )
        self.assertEqual(
            table_input["StorageDescriptor"]["SerdeInfo"]["SerializationLibrary"],
            "org.apache.hive.hcatalog.data.JsonSerDe",
        )

    def test_update_does_not_shrink_registered_schema(self):
        """A run whose source omitted an optional field must not narrow Glue.

        Spark/UC issues ``CREATE TABLE IF NOT EXISTS`` and is a no-op on an
        existing table, so UC keeps its accumulated union. Glue's
        ``update_table`` replaces ``Columns``, which is how
        ``datalake_itau_statements_raw`` lost ``origin_complement`` on the Glue
        side only and broke the EMR read with ``UNRESOLVED_COLUMN``.
        """
        from unittest.mock import MagicMock

        glue_client = MagicMock()
        glue_client.get_table.return_value = {
            "Name": "statement_879200426887",
            "Parameters": {"classification": "json"},
            "StorageDescriptor": {
                "Columns": [
                    {"Name": "id", "Type": "string"},
                    {"Name": "origin_complement", "Type": "string"},
                    {"Name": "amount_value", "Type": "double"},
                ]
            },
        }
        svc = GlueMetastoreService(glue_client)
        # This run's payload omitted origin_complement.
        schema = OrderedDict([("id", "string"), ("amount_value", "double")])
        svc.create_external_table(
            database_name="datalake_itau_statements_raw",
            table_name="statement_879200426887",
            table_location="s3://bucket/raw/itau_statements/statement_879200426887",
            table_schema=schema,
            partition_cols=[],
            format_options="JSON",
        )
        table_input = glue_client.update_table.call_args[0][1]
        self.assertEqual(
            [col["Name"] for col in table_input["StorageDescriptor"]["Columns"]],
            ["id", "origin_complement", "amount_value"],
        )

    def test_merge_does_not_reintroduce_partition_keys_as_columns(self):
        """A table registered elsewhere may hold partition keys in Columns.

        Glue rejects a column that also appears in PartitionKeys, and
        CompositeMetastoreService swallows Glue failures as warnings, so
        carrying them over from the existing table would drift silently.
        """
        from unittest.mock import MagicMock

        glue_client = MagicMock()
        glue_client.get_table.return_value = {
            "Name": "statement_067000392216",
            "Parameters": {"classification": "json"},
            "StorageDescriptor": {
                "Columns": [
                    {"Name": "id", "Type": "string"},
                    {"Name": "origin_complement", "Type": "string"},
                    # Registered by a crawler / Athena DDL that did not split.
                    {"Name": "year", "Type": "int"},
                    {"Name": "Month", "Type": "int"},
                ]
            },
        }
        svc = GlueMetastoreService(glue_client)
        schema = OrderedDict(
            [("id", "string"), ("year", "int"), ("month", "int"), ("day", "int")]
        )
        svc.create_external_table(
            database_name="datalake_itau_statements_raw",
            table_name="statement_067000392216",
            table_location="s3://bucket/raw/itau_statements/statement_067000392216",
            table_schema=schema,
            partition_cols=["year", "month", "day"],
            format_options="JSON",
        )
        table_input = glue_client.update_table.call_args[0][1]
        column_names = [
            col["Name"] for col in table_input["StorageDescriptor"]["Columns"]
        ]
        # origin_complement still preserved, partition keys not duplicated.
        self.assertEqual(column_names, ["id", "origin_complement"])
        self.assertEqual(
            [key["Name"] for key in table_input["PartitionKeys"]],
            ["year", "month", "day"],
        )

    def test_create_path_uses_incoming_schema_only(self):
        """Nothing to merge when the table does not exist yet."""
        from unittest.mock import MagicMock

        glue_client = MagicMock()
        glue_client.get_table.return_value = None
        svc = GlueMetastoreService(glue_client)
        schema = OrderedDict([("id", "string"), ("amount_value", "double")])
        svc.create_external_table(
            database_name="datalake_itau_statements_raw",
            table_name="statement_new",
            table_location="s3://bucket/raw/itau_statements/statement_new",
            table_schema=schema,
            partition_cols=[],
            format_options="JSON",
        )
        glue_client.update_table.assert_not_called()
        table_input = glue_client.create_table.call_args[0][1]
        self.assertEqual(
            [col["Name"] for col in table_input["StorageDescriptor"]["Columns"]],
            ["id", "amount_value"],
        )


class TestGlueMetastoreServiceSplitColumns(unittest.TestCase):
    """Partition columns must be excluded from ``Columns`` case-insensitively.

    Glue lower-cases column names, so a partition column declared as ``Year``
    against a schema holding ``year`` would otherwise appear in both
    ``StorageDescriptor.Columns`` and ``PartitionKeys`` and be rejected as a
    duplicate. Glue failures are swallowed as warnings by
    ``CompositeMetastoreService``, so this would drift silently.
    """

    def test_partition_column_excluded_when_casing_matches(self):
        schema = OrderedDict([("id", "bigint"), ("year", "int")])

        regular, partitioned = GlueMetastoreService._split_columns(schema, ["year"])

        self.assertEqual(regular, [("id", "bigint")])
        self.assertEqual(partitioned, [("year", "int")])

    def test_partition_column_excluded_when_casing_differs(self):
        schema = OrderedDict([("id", "bigint"), ("year", "int")])

        regular, partitioned = GlueMetastoreService._split_columns(schema, ["Year"])

        self.assertEqual(regular, [("id", "bigint")], "year leaked into Columns")
        # Type is resolved from the schema despite the casing mismatch.
        self.assertEqual(partitioned, [("Year", "int")])

    def test_no_duplicate_reaches_table_input(self):
        """End-to-end through _build_table_input, which is what Glue receives."""
        schema = OrderedDict([("id", "bigint"), ("year", "int"), ("month", "int")])

        table_input = GlueMetastoreService._build_table_input(
            table_name="t",
            table_location="s3://bucket/t",
            table_schema=schema,
            partition_cols=["Year", "Month"],
            format_str="JSON",
        )

        column_names = [
            c["Name"].lower() for c in table_input["StorageDescriptor"]["Columns"]
        ]
        partition_names = [c["Name"].lower() for c in table_input["PartitionKeys"]]

        self.assertEqual(column_names, ["id"])
        self.assertEqual(partition_names, ["year", "month"])
        self.assertEqual(set(column_names) & set(partition_names), set())

    def test_typed_tuple_partitions_still_work(self):
        schema = OrderedDict([("id", "bigint"), ("year", "int")])

        regular, partitioned = GlueMetastoreService._split_columns(
            schema, [("Year", "string")]
        )

        self.assertEqual(regular, [("id", "bigint")])
        self.assertEqual(partitioned, [("Year", "string")])
