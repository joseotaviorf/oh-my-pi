"""
Unit tests for build_inference_status_dataframe in
load_vocs_machina_inference_status_raw.py.

Regression coverage for VOCS-34 dh-review: spark.createDataFrame(records)
with no explicit schema raises "can not infer schema from empty dataset"
when records is empty (e.g. quintoml's active-prompt manifest has zero
active prompts for a run). Same sys.modules-mocking convention as
test/dags/cross/base/spark_jobs/test_load_api_ingestion_raw.py -- pyspark and
the bietlejuice runtime deps aren't importable in this environment, so the
whole module tree is stubbed with MagicMock before importing the job.
"""

import sys
from unittest.mock import MagicMock

sys.modules["boto3"] = MagicMock()
sys.modules["pyspark"] = MagicMock()
sys.modules["pyspark.sql"] = MagicMock()
sys.modules["quintoandar_logger"] = MagicMock()
sys.modules["bietlejuice.base.db"] = MagicMock()
sys.modules["bietlejuice.base.spark"] = MagicMock()
sys.modules["bietlejuice.clients.db_clients"] = MagicMock()
sys.modules["bietlejuice.loaders"] = MagicMock()
sys.modules["bietlejuice.loaders.s3_loader"] = MagicMock()
sys.modules["bietlejuice.services.metastore_services"] = MagicMock()

from dags.for_rent.vocs_machina_planning.spark_jobs import (  # noqa: E402
    load_vocs_machina_inference_status_raw as job,
)


class TestBuildInferenceStatusDataframe:
    def test_empty_rows_passes_an_explicit_schema(self):
        job.spark = MagicMock()

        job.build_inference_status_dataframe([])

        job.spark.createDataFrame.assert_called_once_with(
            [], schema=job.INFERENCE_STATUS_SCHEMA
        )

    def test_nonempty_rows_still_passes_the_same_schema(self):
        job.spark = MagicMock()

        job.build_inference_status_dataframe(
            [
                {
                    "day": "2026-05-03",
                    "prompt_id": "nps_churn",
                    "prompt_hash": "abc123",
                    "inference_status": "done",
                }
            ]
        )

        args, kwargs = job.spark.createDataFrame.call_args
        assert len(args[0]) == 1
        assert kwargs["schema"] == job.INFERENCE_STATUS_SCHEMA
