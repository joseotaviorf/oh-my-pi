from bietlejuice.base.pipeline.metadata_type_enum import MetadataTypeEnum
from bietlejuice.metadata_propagator_pipeline.datahub_quality_metrics_pipeline import (
    DatahubQualityMetricsPipeline,
)

_VALIDATION_RESULTS = {
    "metadata": {
        "suite_result": "SUCCESS",
        "run_date": "2026-07-29 18:00:00",
        "success_rate": 1.0,
    },
    "validations": [
        {"column": "id", "validation": "is_unique", "result": 1.0, "status": "Success"}
    ],
}


def _pipeline(platforms=None):
    return DatahubQualityMetricsPipeline(
        metadata_propagator_host="http://mp",
        database_name="datalake_x_clean",
        table_name="my_table",
        metadata_type=MetadataTypeEnum.QUALITY_METRICS,
        validation_results=_VALIDATION_RESULTS,
        platforms=platforms,
    )


def test_payload_includes_platforms_when_resolved():
    payload = _pipeline(
        platforms=["databricks", "glue", "trino"]
    ).build_metadata_propagator_payload()
    assert payload[0]["platforms"] == ["databricks", "glue", "trino"]


def test_payload_omits_platforms_when_absent():
    # None => propagator keeps the legacy single-target behavior; key must be absent
    # (backward-compatible with older propagators that don't read it).
    payload = _pipeline(platforms=None).build_metadata_propagator_payload()
    assert "platforms" not in payload[0]


def test_payload_omits_platforms_when_empty():
    payload = _pipeline(platforms=[]).build_metadata_propagator_payload()
    assert "platforms" not in payload[0]
