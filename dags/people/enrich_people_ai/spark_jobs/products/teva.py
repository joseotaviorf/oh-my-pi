"""Teva product adapter for the generic People AI enrichment runner."""

from __future__ import annotations

import json
import re
from datetime import datetime
from typing import Optional

from pyspark.sql.types import (
    IntegerType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)

from dags.people.enrich_people_ai.spark_jobs.lib import (
    teva_legacy_prompt as teva_prompt,
)

INPUT_DATABASE = "datalake_people"
INPUT_TABLE = "teva_survey_inputs"
MERGE_ON = ["survey_invite_id"]

_JSON_OBJECT_PATTERN = re.compile(r"\{[\s\S]*\}")

_LLM_JSON_KEY_TO_COLUMN = {
    "executive_summary": "ai_executive_summary",
    "pillar_1_2_strategy_goals": "ai_pillar_strategy_and_goals",
    "pillar_3_roles": "ai_pillar_roles_and_accountabilities",
    "pillar_4_protocols": "ai_pillar_protocols_and_ways_of_working",
    "pillar_5_trust": "ai_pillar_trust_and_relationships",
    "additional_comments": "ai_additional_comments_summary",
    "pillar_strategy_and_goals": "ai_pillar_strategy_and_goals",
    "pillar_roles_and_accountabilities": "ai_pillar_roles_and_accountabilities",
    "pillar_protocols_and_ways_of_working": ("ai_pillar_protocols_and_ways_of_working"),
    "pillar_trust_and_relationships": "ai_pillar_trust_and_relationships",
    "additional_comments_summary": "ai_additional_comments_summary",
}


def build_output_schema() -> StructType:
    """Return the governed Delta schema for Teva summaries."""
    return StructType(
        [
            StructField("survey_invite_id", StringType(), False),
            StructField("survey_title", StringType(), True),
            StructField("requester_email", StringType(), True),
            StructField("answered_count", IntegerType(), True),
            StructField("ai_executive_summary", StringType(), True),
            StructField("ai_pillar_strategy_and_goals", StringType(), True),
            StructField("ai_pillar_roles_and_accountabilities", StringType(), True),
            StructField("ai_pillar_protocols_and_ways_of_working", StringType(), True),
            StructField("ai_pillar_trust_and_relationships", StringType(), True),
            StructField("ai_additional_comments_summary", StringType(), True),
            StructField("ts_ai_summary_generated", TimestampType(), False),
        ]
    )


def _split_score_list(value: Optional[str]) -> Optional[list]:
    """Turn a comma-separated Likert string into a list."""
    if not value:
        return None
    parts = [part.strip() for part in str(value).split(",") if part.strip()]
    if not parts:
        return None
    parsed = []
    for part in parts:
        try:
            parsed.append(int(part))
        except ValueError:
            parsed.append(part)
    return parsed


def _split_answer_list(value: Optional[str]) -> Optional[list]:
    """Turn pipe-separated open answers into a list."""
    if not value:
        return None
    parts = [part.strip() for part in str(value).split(" | ") if part.strip()]
    return parts or None


def _survey_data_payload(row: dict) -> str:
    """Build the question-title JSON payload expected by the Teva prompt."""
    payload = {
        teva_prompt.PAYLOAD_KEY_STRATEGIC_GOALS: _split_score_list(
            row.get("strategic_goals_clarity_scores")
        ),
        teva_prompt.PAYLOAD_KEY_PRIORITIES: _split_answer_list(
            row.get("top_priorities_answers")
        ),
        teva_prompt.PAYLOAD_KEY_CHALLENGES: _split_answer_list(
            row.get("team_challenges_answers")
        ),
        teva_prompt.PAYLOAD_KEY_OWN_ROLE: _split_score_list(
            row.get("own_role_clarity_scores")
        ),
        teva_prompt.PAYLOAD_KEY_OTHERS_ROLE: _split_score_list(
            row.get("others_role_clarity_scores")
        ),
        teva_prompt.PAYLOAD_KEY_CURRENT_TEAMWORK: _split_score_list(
            row.get("current_teamwork_scores")
        ),
        teva_prompt.PAYLOAD_KEY_IDEAL_TEAMWORK: _split_answer_list(
            row.get("ideal_teamwork_answers")
        ),
        teva_prompt.PAYLOAD_KEY_DECISIONS: _split_score_list(
            row.get("decision_making_effectiveness_scores")
        ),
        teva_prompt.PAYLOAD_KEY_MEETINGS: _split_score_list(
            row.get("meeting_effectiveness_scores")
        ),
        teva_prompt.PAYLOAD_KEY_OPERATES: _split_score_list(
            row.get("team_performance_scores")
        ),
        teva_prompt.PAYLOAD_KEY_TAKE_TO_BE_5: _split_answer_list(
            row.get("improvement_to_perfect_score_answers")
        ),
        teva_prompt.PAYLOAD_KEY_ATMOSPHERE: _split_score_list(
            row.get("team_atmosphere_scores")
        ),
        teva_prompt.PAYLOAD_KEY_OPENNESS: _split_answer_list(
            row.get("openness_issues_answers")
        ),
        teva_prompt.PAYLOAD_KEY_CONFLICTS: _split_score_list(
            row.get("conflict_handling_scores")
        ),
        teva_prompt.PAYLOAD_KEY_ADJECTIVE: _split_answer_list(
            row.get("team_adjective_answers")
        ),
        teva_prompt.PAYLOAD_KEY_LEADER: _split_answer_list(
            row.get("leader_feedback_answers")
        ),
        teva_prompt.PAYLOAD_KEY_ADDITIONAL: _split_answer_list(
            row.get("additional_comments_answers")
        ),
    }
    return json.dumps(payload, ensure_ascii=False)


def build_prompt(row: dict) -> str:
    """Build the Teva prompt from one prepared survey input row."""
    reference_guide = row.get("reference_guide_text") or ""
    return (
        f"{teva_prompt.PILLAR_THEORY_AND_SPECIALIST_INTRO}\n\n"
        f"{teva_prompt.REFERENCE_GUIDE_HEADER}\n"
        f"{reference_guide}\n\n"
        f"{teva_prompt.PILLAR_TASKS_AND_JSON_CONTRACT}\n\n"
        f"{teva_prompt.ENGLISH_OUTPUT_INSTRUCTION}\n\n"
        f"{_survey_data_payload(row)}"
    )


def _section_text(value) -> Optional[str]:
    """Flatten a JSON section to a string."""
    if value is None:
        return None
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        parts = []
        for key, nested in value.items():
            if nested is None or nested == "":
                continue
            parts.append(f"[{key}]: {nested}")
        return "\n".join(parts) if parts else None
    return str(value)


def parse_response(
    row: dict, raw_response: str, generated_at: datetime
) -> Optional[dict]:
    """Parse and shape one Teva model response."""
    stripped = raw_response.strip()
    if stripped.startswith("```"):
        lines = stripped.splitlines()
        if len(lines) >= 2 and lines[-1].strip() == "```":
            stripped = "\n".join(lines[1:-1]).strip()
    match = _JSON_OBJECT_PATTERN.search(stripped)
    if not match:
        return None
    try:
        parsed = json.loads(match.group(0))
    except json.JSONDecodeError:
        return None

    survey_invite_id = row.get("survey_invite_id")
    if not survey_invite_id:
        return None
    result = {
        "survey_invite_id": survey_invite_id,
        "survey_title": row.get("survey_title"),
        "requester_email": row.get("requester_email"),
        "answered_count": row.get("answered_count"),
        "ts_ai_summary_generated": generated_at,
    }
    for column_name in _LLM_JSON_KEY_TO_COLUMN.values():
        result.setdefault(column_name, None)
    for json_key, column_name in _LLM_JSON_KEY_TO_COLUMN.items():
        if result.get(column_name) is not None:
            continue
        if json_key in parsed:
            result[column_name] = _section_text(parsed.get(json_key))
    return result
