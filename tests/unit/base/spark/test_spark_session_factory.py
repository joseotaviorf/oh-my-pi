from unittest.mock import MagicMock, patch

from bietlejuice.base.spark.spark_session_factory import create_emr_spark_session


@patch("bietlejuice.base.spark.spark_session_factory.SparkSession")
def test_create_emr_spark_session_configures_delta_and_hive(mock_spark_session):
    builder = MagicMock()
    mock_spark_session.builder.appName.return_value = builder
    builder.config.return_value = builder
    builder.enableHiveSupport.return_value = builder
    sess = MagicMock()
    builder.getOrCreate.return_value = sess

    out = create_emr_spark_session("my_job")

    assert out is sess
    mock_spark_session.builder.appName.assert_called_once_with("my_job")
    builder.config.assert_any_call(
        "spark.hadoop.fs.s3a.acl.default", "BucketOwnerFullControl"
    )
    builder.config.assert_any_call(
        "spark.hadoop.fs.s3a.canned.acl", "BucketOwnerFullControl"
    )
    builder.enableHiveSupport.assert_called_once()


@patch("bietlejuice.base.spark.spark_session_factory.SparkSession")
def test_create_emr_spark_session_applies_extra_configs(mock_spark_session):
    builder = MagicMock()
    mock_spark_session.builder.appName.return_value = builder
    builder.config.return_value = builder
    builder.enableHiveSupport.return_value = builder
    sess = MagicMock()
    builder.getOrCreate.return_value = sess

    out = create_emr_spark_session(
        "my_job", extra_configs={"spark.foo": "bar", "spark.baz": 1}
    )

    assert out is sess
    assert builder.config.call_count == 6
