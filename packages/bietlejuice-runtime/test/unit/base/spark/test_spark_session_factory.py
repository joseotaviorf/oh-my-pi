from unittest.mock import MagicMock, patch

from bietlejuice.base.spark.spark_session_factory import (
    create_emr_spark_session,
    run_spark_entrypoint,
)


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


@patch("bietlejuice.base.spark.spark_session_factory.SparkSession")
def test_create_emr_spark_session_merges_cluster_extensions(mock_spark_session):
    builder = MagicMock()
    mock_spark_session.builder.appName.return_value = builder
    builder.config.return_value = builder
    builder.enableHiveSupport.return_value = builder
    sess = MagicMock()
    builder.getOrCreate.return_value = sess

    create_emr_spark_session(
        "my_job",
        extra_configs={
            "spark.sql.extensions": (
                "org.apache.sedona.viz.sql.SedonaVizExtensions,"
                "org.apache.sedona.sql.SedonaSqlExtensions"
            ),
            "spark.kryo.registrator": "org.apache.sedona.core.serde.SedonaKryoRegistrator",
        },
    )

    builder.config.assert_any_call(
        "spark.sql.extensions",
        (
            "io.delta.sql.DeltaSparkSessionExtension,"
            "org.apache.sedona.viz.sql.SedonaVizExtensions,"
            "org.apache.sedona.sql.SedonaSqlExtensions"
        ),
    )
    builder.config.assert_any_call(
        "spark.kryo.registrator",
        "org.apache.sedona.core.serde.SedonaKryoRegistrator",
    )


class _ExitRecorded(Exception):
    def __init__(self, code):
        self.code = code
        super().__init__(code)


def _patch_exit(mock_exit):
    def _raise(code):
        raise _ExitRecorded(code)

    mock_exit.side_effect = _raise


@patch("bietlejuice.base.spark.spark_session_factory.os._exit")
@patch("bietlejuice.base.spark.spark_session_factory.SparkSession")
@patch(
    "bietlejuice.base.spark.runtime_detector.RuntimeDetector.is_emr", return_value=True
)
def test_run_spark_entrypoint_stops_immediately_on_success(
    _mock_is_emr, mock_spark_session, mock_exit
):
    import time

    session = MagicMock()
    mock_spark_session.getActiveSession.return_value = session
    _patch_exit(mock_exit)

    started = time.monotonic()
    try:
        run_spark_entrypoint(lambda: None)
    except _ExitRecorded as exc:
        elapsed = time.monotonic() - started
        assert exc.code == 0
        assert elapsed < 1
        session.stop.assert_called_once()
    else:
        raise AssertionError("expected os._exit to stop control flow")


@patch("bietlejuice.base.spark.spark_session_factory.os._exit")
@patch("bietlejuice.base.spark.spark_session_factory.SparkSession")
@patch(
    "bietlejuice.base.spark.runtime_detector.RuntimeDetector.is_emr", return_value=True
)
def test_run_spark_entrypoint_caps_wedged_stop(
    _mock_is_emr, mock_spark_session, mock_exit
):
    import threading
    import time

    session = MagicMock()
    block = threading.Event()
    session.stop.side_effect = lambda: block.wait()
    mock_spark_session.getActiveSession.return_value = session
    _patch_exit(mock_exit)

    started = time.monotonic()
    try:
        run_spark_entrypoint(lambda: None, stop_timeout_seconds=1)
    except _ExitRecorded as exc:
        elapsed = time.monotonic() - started
        assert exc.code == 0
        assert 0.9 <= elapsed < 3
    else:
        raise AssertionError("expected os._exit to stop control flow")
    finally:
        block.set()


@patch("bietlejuice.base.spark.spark_session_factory.os._exit")
@patch("bietlejuice.base.spark.spark_session_factory.SparkSession")
@patch(
    "bietlejuice.base.spark.runtime_detector.RuntimeDetector.is_emr", return_value=True
)
def test_run_spark_entrypoint_maps_exception_to_exit_1(
    _mock_is_emr, mock_spark_session, mock_exit
):
    session = MagicMock()
    mock_spark_session.getActiveSession.return_value = session
    _patch_exit(mock_exit)

    def boom():
        raise RuntimeError("job failed")

    try:
        run_spark_entrypoint(boom)
    except _ExitRecorded as exc:
        assert exc.code == 1
        session.stop.assert_called_once()
    else:
        raise AssertionError("expected os._exit to stop control flow")


@patch("bietlejuice.base.spark.spark_session_factory.os._exit")
@patch("bietlejuice.base.spark.spark_session_factory.SparkSession")
@patch(
    "bietlejuice.base.spark.runtime_detector.RuntimeDetector.is_emr", return_value=True
)
def test_run_spark_entrypoint_exits_when_no_active_session(
    _mock_is_emr, mock_spark_session, mock_exit
):
    mock_spark_session.getActiveSession.return_value = None
    _patch_exit(mock_exit)

    try:
        run_spark_entrypoint(lambda: None)
    except _ExitRecorded as exc:
        assert exc.code == 0
    else:
        raise AssertionError("expected os._exit to stop control flow")


@patch("bietlejuice.base.spark.spark_session_factory.os._exit")
@patch("bietlejuice.base.spark.spark_session_factory.SparkSession")
@patch(
    "bietlejuice.base.spark.runtime_detector.RuntimeDetector.is_emr", return_value=False
)
def test_run_spark_entrypoint_non_emr_success_returns(
    _mock_is_emr, mock_spark_session, mock_exit
):
    session = MagicMock()
    mock_spark_session.getActiveSession.return_value = session

    assert run_spark_entrypoint(lambda: None) is None
    mock_exit.assert_not_called()
    session.stop.assert_not_called()


@patch("bietlejuice.base.spark.spark_session_factory.os._exit")
@patch("bietlejuice.base.spark.spark_session_factory.SparkSession")
@patch(
    "bietlejuice.base.spark.runtime_detector.RuntimeDetector.is_emr", return_value=False
)
def test_run_spark_entrypoint_non_emr_failure_raises_system_exit(
    _mock_is_emr, mock_spark_session, mock_exit
):
    session = MagicMock()
    mock_spark_session.getActiveSession.return_value = session

    def boom():
        raise RuntimeError("job failed")

    try:
        run_spark_entrypoint(boom)
    except SystemExit as exc:
        assert exc.code == 1
        mock_exit.assert_not_called()
        session.stop.assert_not_called()
    else:
        raise AssertionError("expected SystemExit(1)")


@patch("bietlejuice.base.spark.spark_session_factory.os._exit")
@patch("bietlejuice.base.spark.spark_session_factory.SparkSession")
@patch(
    "bietlejuice.base.spark.runtime_detector.RuntimeDetector.is_emr", return_value=True
)
def test_run_spark_entrypoint_preserves_system_exit_0(
    _mock_is_emr, mock_spark_session, mock_exit
):
    session = MagicMock()
    mock_spark_session.getActiveSession.return_value = session
    _patch_exit(mock_exit)

    try:
        run_spark_entrypoint(lambda: (_ for _ in ()).throw(SystemExit(0)))
    except _ExitRecorded as exc:
        assert exc.code == 0
        session.stop.assert_called_once()
    else:
        raise AssertionError("expected os._exit to stop control flow")
