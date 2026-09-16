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
        _build_teva_prompt,
        _extract_json_object,
        _generate_summary,
        _survey_data_payload,
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
        self.assertIn("Grow the team | Ship faster", prompt)
        self.assertIn("executive_summary", prompt)


class TestSurveyDataPayload(unittest.TestCase):
    def test_serializes_all_expected_fields(self):
        payload = json.loads(_survey_data_payload(SAMPLE_ROW))
        self.assertEqual(payload["strategic_goals_clarity_scores"], "4,5,3")
        self.assertEqual(
            payload["top_priorities_answers"], "Grow the team | Ship faster"
        )

    def test_missing_fields_serialize_as_null(self):
        payload = json.loads(_survey_data_payload({"survey_invite_id": "x"}))
        self.assertIsNone(payload["strategic_goals_clarity_scores"])


class TestGenerateSummary(unittest.TestCase):
    def test_returns_none_without_survey_invite_id(self):
        client = MagicMock()
        self.assertIsNone(_generate_summary({}, client))
        client.complete.assert_not_called()

    def test_returns_none_when_llm_response_is_not_parseable_json(self):
        client = MagicMock()
        client.complete.return_value = "not json at all"
        self.assertIsNone(_generate_summary(SAMPLE_ROW, client))

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
                "pillar_strategy_and_goals": "Aligned priorities.",
                "pillar_roles_and_accountabilities": "Clear roles.",
                "pillar_protocols_and_ways_of_working": "Fast decisions.",
                "pillar_trust_and_relationships": "High trust.",
                "additional_comments_summary": "No new themes.",
            }
        )
        result = _generate_summary(SAMPLE_ROW, client)
        self.assertEqual(result["survey_invite_id"], "invite-123")
        self.assertEqual(result["ai_executive_summary"], "Overall positive.")
        self.assertEqual(result["ai_pillar_trust_and_relationships"], "High trust.")
        self.assertIn("ts_ai_summary_generated", result)


if __name__ == "__main__":
    unittest.main()
