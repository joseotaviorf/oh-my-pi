from datetime import datetime
from unittest.mock import patch

import pytest

from dags.people.enrich_people_ai.spark_jobs.lib.ai_enrichment import (
    AIProduct,
    AIProductConfig,
    collect_generated_rows,
)


class FakeClient:
    def __init__(self, response):
        self.response = response
        self.prompts = []

    def complete(self, prompt):
        self.prompts.append(prompt)
        return self.response


class FakeLogger:
    def __init__(self):
        self.warnings = []

    def warning(self, *args):
        self.warnings.append(args)


def _build_product(parse_response):
    return AIProduct(
        key="test_product",
        input_database="datalake_people",
        input_table="test_inputs",
        merge_on=["id_record"],
        build_prompt=lambda row: f"prompt:{row['id_record']}",
        parse_response=parse_response,
        build_output_schema=lambda: None,
        config=AIProductConfig(
            model="test/model",
            max_calls_per_run=10,
            max_concurrency=2,
            prompt_version="test",
            processing_mode="new_only",
            temperature=0.2,
            max_tokens=100,
            timeout_seconds=10,
            max_retries=1,
        ),
    )


def test_collect_generated_rows_uses_product_contract():
    client = FakeClient("model response")
    logger = FakeLogger()
    product = _build_product(
        lambda row, response, generated_at: {
            "id_record": row["id_record"],
            "text": response,
            "generated_at": generated_at,
        }
    )

    result = collect_generated_rows(
        pending_rows=[{"id_record": "1"}],
        client=client,
        product=product,
        logger=logger,
    )

    assert result[0]["id_record"] == "1"
    assert result[0]["text"] == "model response"
    assert isinstance(result[0]["generated_at"], datetime)
    assert client.prompts == ["prompt:1"]
    assert logger.warnings == []


def test_collect_generated_rows_fails_when_all_responses_are_invalid():
    client = FakeClient("invalid")
    logger = FakeLogger()
    product = _build_product(lambda row, response, generated_at: None)

    with pytest.raises(RuntimeError, match="no parseable test_product rows"):
        collect_generated_rows(
            pending_rows=[{"id_record": "1"}],
            client=client,
            product=product,
            logger=logger,
        )

    assert len(logger.warnings) == 1


def test_collect_generated_rows_skips_missing_merge_keys_without_calling_model():
    client = FakeClient("should not be called")
    logger = FakeLogger()
    product = _build_product(lambda row, response, generated_at: None)

    with pytest.raises(RuntimeError, match="no parseable test_product rows"):
        collect_generated_rows(
            pending_rows=[{"id_record": None}],
            client=client,
            product=product,
            logger=logger,
        )

    assert client.prompts == []
    assert "missing merge keys" in logger.warnings[0][0]


def test_collect_generated_rows_uses_configured_concurrency():
    client = FakeClient("model response")
    logger = FakeLogger()
    product = _build_product(
        lambda row, response, generated_at: {"id_record": row["id_record"]}
    )

    with patch(
        "dags.people.enrich_people_ai.spark_jobs.lib.ai_enrichment.ThreadPoolExecutor"
    ) as executor_class:
        executor = executor_class.return_value.__enter__.return_value
        executor.map.return_value = [
            ("1", {"id_record": "1"}, "model response"),
            ("2", {"id_record": "2"}, "model response"),
        ]

        result = collect_generated_rows(
            pending_rows=[{"id_record": "1"}, {"id_record": "2"}],
            client=client,
            product=product,
            logger=logger,
        )

    executor_class.assert_called_once_with(max_workers=2)
    assert result == [{"id_record": "1"}, {"id_record": "2"}]
