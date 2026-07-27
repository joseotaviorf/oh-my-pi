from bietlejuice.base.pipeline import MetadataTypeEnum
from bietlejuice.metadata_propagator_pipeline.datahub_quality_metrics_pipeline import (
    DatahubQualityMetricsPipeline,
)

VALIDATION_RESULTS = {
    "metadata": {
        "suite_result": "success",
        "run_date": "2021-10-25T17:35:00",
        "success_rate": 1.0,
    },
    "validations": [{"column": "id", "validation": "is_unique", "status": "Success"}],
}


def _payload(platforms):
    pipeline = DatahubQualityMetricsPipeline(
        metadata_propagator_host="http://host",
        database_name="dw_rent",
        table_name="dim_contract",
        metadata_type=MetadataTypeEnum.QUALITY_METRICS,
        validation_results=VALIDATION_RESULTS,
        platforms=platforms,
    )
    return pipeline.build_metadata_propagator_payload()[0]


class TestDatahubQualityMetricsPipelinePayload:
    def test_includes_platforms_when_set(self):
        payload = _payload(["databricks", "glue", "trino"])
        assert payload["platforms"] == ["databricks", "glue", "trino"]
        # core fields still present
        assert payload["vendor"] == ["datahub"]
        assert payload["database_name"] == "dw_rent"
        assert payload["table_name"] == "dim_contract"

    def test_omits_platforms_when_none(self):
        payload = _payload(None)
        assert "platforms" not in payload

    def test_omits_platforms_when_empty(self):
        payload = _payload([])
        assert "platforms" not in payload
