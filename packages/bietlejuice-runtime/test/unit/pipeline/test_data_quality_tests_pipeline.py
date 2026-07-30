from types import SimpleNamespace

from bietlejuice.pipeline import data_quality_tests_pipeline
from bietlejuice.pipeline.data_quality_tests_pipeline import DataQualityTestsPipeline


class _ValidationSuiteBuilder:
    def __init__(self, _client):
        pass

    def build_validation_suite_from_input_config(self, _input_configs):
        return "validation-suite"


def _pipeline():
    pipeline = DataQualityTestsPipeline.__new__(DataQualityTestsPipeline)
    pipeline.spark_client = SimpleNamespace(conn="spark")
    return pipeline


def test_execute_test_passes_table_identifier_when_supported(monkeypatch):
    captured = {}

    class Validator:
        def __init__(self, suite_name, validation_suite, client, table_identifier=None):
            captured.update(
                suite_name=suite_name,
                validation_suite=validation_suite,
                client=client,
                table_identifier=table_identifier,
            )

        def execute_and_parse(self, _df):
            return {"status": "success"}

    # Arrange
    monkeypatch.setattr(
        data_quality_tests_pipeline, "ValidationSuiteBuilder", _ValidationSuiteBuilder
    )
    monkeypatch.setattr(data_quality_tests_pipeline, "PyDeequValidator", Validator)

    # Act
    result = _pipeline()._execute_test({}, "database", "table", object())

    # Assert
    assert result == {"status": "success"}
    assert captured["table_identifier"] == "database.table"


def test_execute_test_omits_table_identifier_when_unsupported(monkeypatch):
    captured = {}

    class LegacyValidator:
        def __init__(self, suite_name, validation_suite, client):
            captured.update(
                suite_name=suite_name,
                validation_suite=validation_suite,
                client=client,
            )

        def execute_and_parse(self, _df):
            return {"status": "success"}

    # Arrange
    monkeypatch.setattr(
        data_quality_tests_pipeline, "ValidationSuiteBuilder", _ValidationSuiteBuilder
    )
    monkeypatch.setattr(
        data_quality_tests_pipeline, "PyDeequValidator", LegacyValidator
    )

    # Act
    result = _pipeline()._execute_test({}, "database", "table", object())

    # Assert
    assert result == {"status": "success"}
    assert captured["suite_name"] == "Pipeline Validations: database.table"


def test_publish_to_metadata_propagator_is_best_effort(monkeypatch):
    # A metadata-propagator failure (outage/timeout/rejected payload) must NOT
    # propagate: publishing DQ metrics is a side-effect and cannot fail the DQ
    # pipeline (which would fail the DAG). The error is logged and swallowed.
    class _Dbutils:
        secrets = SimpleNamespace(get=lambda scope, key: '{"host": "http://mp"}')

    class _BaseDBUtils:
        def get_dbutils(self):
            return _Dbutils()

    class _FailingPipeline:
        def __init__(self, **_kwargs):
            pass

        def run(self):
            raise RuntimeError("metadata-propagator down")

    monkeypatch.setattr(data_quality_tests_pipeline, "BaseDBUtils", _BaseDBUtils)
    monkeypatch.setattr(
        data_quality_tests_pipeline, "DatahubQualityMetricsPipeline", _FailingPipeline
    )

    pipeline = _pipeline()
    pipeline.platforms = ["databricks", "glue"]

    # Act & Assert: must not raise despite the propagator error
    pipeline._publish_validation_results_to_metadata_propagator(
        {"metadata": {}}, "database", "table"
    )
