import unittest

import pytest

from bietlejuice.base.spark.spark_table_storage_format import SparkTableStorageFormat


class TestSparkTableStorageFormat(unittest.TestCase):
    def test_consumption_is_a_valid_storage(self):
        # Luigi/Zordon materializations declare workflow.layer = "consumption"
        # (MATERIALIZATION_LAYER migration). TableLoaderPipeline.run() calls
        # get_storage(self.layer) unconditionally for every query_delta DAG,
        # Delta-backed or not, so this must not raise.
        self.assertTrue(SparkTableStorageFormat.is_valid_storage("consumption"))

    def test_get_storage_for_consumption_returns_parquet(self):
        self.assertEqual(
            SparkTableStorageFormat.get_storage("consumption"),
            SparkTableStorageFormat.PARQUET,
        )

    def test_get_storage_for_invalid_layer_still_raises(self):
        with pytest.raises(RuntimeError):
            SparkTableStorageFormat.get_storage("not_a_real_layer")
