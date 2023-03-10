from bietlejuice.base.db.metric_metastore_mapping import MetricMetastoreMapping


class TestMetricMetastoreMapping:
    def test_get_all_metric_info(self):
        # arrange
        schema = "_my_schema_"
        metric_bucket = "metric-mock"
        expected = ("metric__my_schema_", "s3a://metric-mock/_my_schema_/")

        # act
        db_info = MetricMetastoreMapping(
            bucket=metric_bucket, source=schema
        ).get_metric_info()

        # assert
        assert db_info == expected
