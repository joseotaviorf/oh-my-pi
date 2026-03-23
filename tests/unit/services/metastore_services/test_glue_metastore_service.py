"""Unit tests for GlueMetastoreService Glue TableInput shape (Delta)."""

import unittest
from collections import OrderedDict

from bietlejuice.services.metastore_services.glue_metastore_service import (
    GlueMetastoreService,
)


class TestGlueMetastoreServiceTableInput(unittest.TestCase):
    """Assert Delta tables use Hive stub SerDe + Spark table properties."""

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
