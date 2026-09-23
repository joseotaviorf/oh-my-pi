import json
from datetime import datetime

from dags.people.enrich_people_ai.spark_jobs.products import teva
from dags.people.enrich_people_ai.spark_jobs.products.registry import get_product


def test_teva_product_exposes_input_and_merge_contract():
    assert teva.INPUT_DATABASE == "datalake_people"
    assert teva.INPUT_TABLE == "teva_survey_inputs"
    assert teva.MERGE_ON == ["survey_invite_id"]
    assert teva.build_output_schema().fieldNames()[-1] == "ts_ai_summary_generated"


def test_teva_product_loads_litellm_settings_from_yaml():
    product = get_product("teva")

    assert product.config.model == "vertex_ai/claude-sonnet-4-5"
    assert product.config.max_calls_per_run == 100
    assert product.config.prompt_version == "v1"
    assert product.config.processing_mode == "new_only"
    assert product.config.max_tokens == 4096


def test_teva_product_parses_model_json_into_governed_columns():
    row = {
        "survey_invite_id": "invite-1",
        "survey_title": "Team survey",
        "requester_email": "requester@quintoandar.com.br",
        "answered_count": 2,
    }

    result = teva.parse_response(
        row,
        json.dumps({"executive_summary": "Positive overall."}),
        generated_at=datetime(2026, 9, 22),
    )

    assert result["survey_invite_id"] == "invite-1"
    assert result["ai_executive_summary"] == "Positive overall."
