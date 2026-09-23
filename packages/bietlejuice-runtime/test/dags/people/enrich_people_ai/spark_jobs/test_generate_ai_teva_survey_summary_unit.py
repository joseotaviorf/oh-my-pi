"""Pure-function unit tests (no Spark runtime required)."""

import json
import sys
import unittest
from unittest.mock import MagicMock, patch

# Module import touches SparkClient/metastore; mock for import only (patch.dict restores sys.modules).
_IMPORT_TIME_MOCKS = {
    "bietlejuice.clients.db_clients": MagicMock(),
    "bietlejuice.services.metastore_services": MagicMock(),
    "quintoandar_logger": MagicMock(),
}
with patch.dict(sys.modules, _IMPORT_TIME_MOCKS):
    from dags.people.enrich_people_ai.spark_jobs.generate_ai_teva_survey_summary import (  # noqa: E402
        _build_pending_df,
        _build_teva_prompt,
        _collect_generated_summaries,
        _extract_json_object,
        _generate_summary,
        _survey_data_payload,
    )
    from dags.people.enrich_people_ai.spark_jobs.generate_ai_teva_survey_summary import (
        logger as teva_job_logger,
    )

SAMPLE_ROW = {
    "survey_invite_id": "invite-123",
    "survey_title": "TEVA | Team | Jan'26",
    "requester_email": "requester@quintoandar.com.br",
    "answered_count": 5,
    "strategic_goals_clarity_scores": "4,5,3",
    "top_priorities_answers": "Grow the team | Ship faster",
    "reference_guide_text": '- "example" (Sentiment: Positive) implies context for Pillar 3',
}


class TestExtractJsonObject(unittest.TestCase):
    def test_parses_plain_json_object(self):
        text = json.dumps({"executive_summary": "All good."})
        parsed = _extract_json_object(text)
        self.assertEqual(parsed, {"executive_summary": "All good."})

    def test_extracts_json_wrapped_in_markdown_fence(self):
        payload = {"executive_summary": "Positive overall."}
        text = f"Here is the analysis:\n```json\n{json.dumps(payload)}\n```"
        parsed = _extract_json_object(text)
        self.assertEqual(parsed, payload)

    def test_returns_none_for_non_json_text(self):
        self.assertIsNone(_extract_json_object("Sorry, I cannot help with that."))

    def test_returns_none_for_malformed_json(self):
        self.assertIsNone(_extract_json_object("{not: valid json}"))


class TestBuildTevaPrompt(unittest.TestCase):
    def test_includes_reference_guide_and_survey_payload(self):
        prompt = _build_teva_prompt(SAMPLE_ROW)
        self.assertIn(SAMPLE_ROW["reference_guide_text"], prompt)
        self.assertIn("Grow the team", prompt)
        self.assertIn("executive_summary", prompt)

    def test_keeps_json_contract_and_english_output(self):
        prompt = _build_teva_prompt(SAMPLE_ROW)
        self.assertIn("pillar_1_2_strategy_goals", prompt)
        self.assertIn("P12: How clear are the strategic goals for this team?", prompt)
        self.assertIn("1 and 2 infer negative", prompt)
        self.assertIn("Write every JSON value in English", prompt)
        self.assertNotIn("same language as the survey answers", prompt)


class TestSurveyDataPayload(unittest.TestCase):
    def test_serializes_question_titles_as_lists(self):
        payload = json.loads(_survey_data_payload(SAMPLE_ROW))
        self.assertEqual(
            payload["P12: How clear are the strategic goals for this team?"],
            [4, 5, 3],
        )
        self.assertEqual(
            payload["What are the top priorities for this team?"],
            ["Grow the team", "Ship faster"],
        )

    def test_missing_fields_serialize_as_null(self):
        payload = json.loads(_survey_data_payload({"survey_invite_id": "x"}))
        self.assertIsNone(
            payload["P12: How clear are the strategic goals for this team?"]
        )


class TestGenerateSummary(unittest.TestCase):
    def test_returns_none_without_survey_invite_id(self):
        client = MagicMock()
        self.assertIsNone(_generate_summary({}, client))
        client.complete.assert_not_called()

    def test_returns_none_when_llm_response_is_not_parseable_json(self):
        client = MagicMock()
        client.complete.return_value = "not json at all"
        teva_job_logger.warning.reset_mock()
        self.assertIsNone(_generate_summary(SAMPLE_ROW, client))
        warning_args = teva_job_logger.warning.call_args[0]
        self.assertIn("preview=%s", warning_args[0])
        self.assertEqual(warning_args[1], "invite-123")
        self.assertEqual(warning_args[2], "not json at all")

    def test_returns_none_when_llm_client_raises_runtime_error(self):
        client = MagicMock()
        client.complete.side_effect = RuntimeError("LiteLLM request failed")
        with self.assertRaises(RuntimeError):
            _generate_summary(SAMPLE_ROW, client)

    def test_maps_parsed_json_keys_into_output_row(self):
        client = MagicMock()
        client.complete.return_value = json.dumps(
            {
                "executive_summary": "Overall positive.",
                "pillar_1_2_strategy_goals": "Aligned priorities.",
                "pillar_3_roles": "Clear roles.",
                "pillar_4_protocols": "Fast decisions.",
                "pillar_5_trust": "High trust.",
                "additional_comments": "No new themes.",
            }
        )
        result = _generate_summary(SAMPLE_ROW, client)
        self.assertEqual(result["survey_invite_id"], "invite-123")
        self.assertEqual(result["ai_executive_summary"], "Overall positive.")
        self.assertEqual(result["ai_pillar_trust_and_relationships"], "High trust.")
        self.assertIn("ts_ai_summary_generated", result)

    def test_flattens_nested_pillar_objects(self):
        client = MagicMock()
        client.complete.return_value = json.dumps(
            {
                "executive_summary": "Positive.",
                "pillar_5_trust": {
                    "issues_impacting_openness": "Meetings too long",
                    "feedback_for_team_leader": "More 1:1s",
                },
            }
        )
        result = _generate_summary(SAMPLE_ROW, client)
        trust = result["ai_pillar_trust_and_relationships"]
        self.assertIn("[issues_impacting_openness]: Meetings too long", trust)
        self.assertIn("[feedback_for_team_leader]: More 1:1s", trust)


class TestCollectGeneratedSummaries(unittest.TestCase):
    def test_propagates_litellm_runtime_error(self):
        """A LiteLLM HTTP failure must fail the job, not skip the row."""
        client = MagicMock()
        client.complete.side_effect = RuntimeError(
            "LiteLLM request failed: HTTP Error 404: Not Found"
        )
        with self.assertRaisesRegex(RuntimeError, "HTTP Error 404"):
            _collect_generated_summaries([SAMPLE_ROW], client)

    def test_raises_when_every_row_is_unparseable(self):
        client = MagicMock()
        client.complete.return_value = "not json at all"
        with self.assertRaises(RuntimeError) as ctx:
            _collect_generated_summaries([SAMPLE_ROW], client)
        self.assertIn("no parseable AI Teva summaries", str(ctx.exception))

    def test_keeps_parseable_rows(self):
        client = MagicMock()
        client.complete.return_value = json.dumps(
            {
                "executive_summary": "Overall positive.",
                "pillar_1_2_strategy_goals": "Aligned priorities.",
                "pillar_3_roles": "Clear roles.",
                "pillar_4_protocols": "Fast decisions.",
                "pillar_5_trust": "High trust.",
                "additional_comments": "No new themes.",
            }
        )
        generated = _collect_generated_summaries([SAMPLE_ROW], client)
        self.assertEqual(len(generated), 1)
        self.assertEqual(generated[0]["ai_executive_summary"], "Overall positive.")


class TestProcessingMode(unittest.TestCase):
    def test_all_mode_limits_inputs_without_reading_existing_rows(self):
        inputs_df = MagicMock()
        inputs_df.orderBy.return_value.limit.return_value = "limited-inputs"
        product = MagicMock()
        product.merge_on = ["survey_invite_id"]

        result = _build_pending_df(
            inputs_df=inputs_df,
            existing_df=MagicMock(),
            product=product,
            processing_mode="all",
            max_calls=10,
        )

        self.assertEqual(result, "limited-inputs")
        inputs_df.orderBy.assert_called_once()
        inputs_df.orderBy.return_value.limit.assert_called_once_with(10)

    def test_rejects_unknown_processing_mode(self):
        with self.assertRaisesRegex(ValueError, "Unknown processing mode"):
            _build_pending_df(
                inputs_df=MagicMock(),
                existing_df=None,
                product=MagicMock(),
                processing_mode="sometimes",
                max_calls=10,
            )


if __name__ == "__main__":
    unittest.main()
