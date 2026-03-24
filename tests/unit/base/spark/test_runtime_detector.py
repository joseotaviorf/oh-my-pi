import os
import unittest
from unittest.mock import patch

from bietlejuice.base.spark.runtime_detector import RuntimeDetector


class TestRuntimeDetector(unittest.TestCase):

    @patch.dict(os.environ, {"SPARK_RUNTIME": "databricks"}, clear=False)
    def test_is_databricks_via_env_var(self):
        self.assertTrue(RuntimeDetector.is_databricks())
        self.assertFalse(RuntimeDetector.is_emr())

    @patch.dict(os.environ, {"SPARK_RUNTIME": "emr"}, clear=False)
    def test_is_emr_via_env_var(self):
        self.assertTrue(RuntimeDetector.is_emr())
        self.assertFalse(RuntimeDetector.is_databricks())

    @patch.dict(os.environ, {"SPARK_RUNTIME": ""}, clear=False)
    def test_unknown_runtime_when_env_var_empty(self):
        self.assertFalse(RuntimeDetector.is_databricks())
        self.assertFalse(RuntimeDetector.is_emr())
        self.assertEqual(RuntimeDetector.runtime_name(), "unknown")

    @patch.dict(os.environ, {"SPARK_RUNTIME": "databricks"}, clear=False)
    def test_runtime_name_databricks(self):
        self.assertEqual(RuntimeDetector.runtime_name(), "databricks")

    @patch.dict(os.environ, {"SPARK_RUNTIME": "emr"}, clear=False)
    def test_runtime_name_emr(self):
        self.assertEqual(RuntimeDetector.runtime_name(), "emr")

    @patch.dict(os.environ, {"SPARK_RUNTIME": "DATABRICKS"}, clear=False)
    def test_env_var_is_case_insensitive(self):
        self.assertTrue(RuntimeDetector.is_databricks())

    @patch.dict(os.environ, {"SPARK_RUNTIME": " EMR "}, clear=False)
    def test_env_var_is_stripped(self):
        self.assertTrue(RuntimeDetector.is_emr())
