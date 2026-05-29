import pytest

pytest.importorskip("pyspark")

from dags.mlops.evidently_ml_monitor.spark_jobs.load_evidently_ml_monitor_raw import (  # noqa: E402
    _read_metric_files,
)


class TestReadMetricFiles:
    def test_rejects_non_parquet_format(self, spark):
        with pytest.raises(ValueError, match="parquet"):
            _read_metric_files(spark, "/tmp/source", "json")

    def test_reads_local_parquet_with_merge_schema(self, spark, tmp_path):
        spark.createDataFrame([(1, "a")], ["id", "value"]).write.mode(
            "overwrite"
        ).parquet(str(tmp_path))

        df = _read_metric_files(spark, str(tmp_path), "parquet")

        assert df.count() == 1
        assert "id" in df.columns
