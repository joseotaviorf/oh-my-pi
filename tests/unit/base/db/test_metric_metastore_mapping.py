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

    def test_get_schema_from_database_for_metric(self):
        # arrange
        database = "metric_my_schema"

        # act
        schema = MetricMetastoreMapping.get_schema_from_database(database)

        # assert
        assert schema == "my_schema"

    def test_get_schema_from_database_for_other(self):
        # arrange
        database = "other"

        # act
        schema = MetricMetastoreMapping.get_schema_from_database(database)

        # assert
        assert schema is None
