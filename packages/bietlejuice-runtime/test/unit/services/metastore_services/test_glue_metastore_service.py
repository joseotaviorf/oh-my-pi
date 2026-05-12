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
