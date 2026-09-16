"""Generate AI Teva survey summaries and load ``datalake_people.ai_teva_survey_summary``.

This Spark job is the EMR/Databricks replacement for the legacy ``ai_teva_update``
notebook. For each pending row in ``datalake_people.teva_survey_inputs`` it builds
a structured LiteLLM prompt, expects a single JSON object in the model reply, maps
that JSON into flat STRING pillar columns, and merges into Delta on ``survey_invite_id``.

Incremental behavior: invites already present in the target table are skipped.
A per-run cap (``--max-calls-per-run``) limits LiteLLM cost.
"""

from __future__ import annotations

import json
import logging
import re
from argparse import ArgumentParser
from datetime import datetime, timezone
from typing import Optional

from pyspark.sql.types import (
    IntegerType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.metastore_services import MetastoreServiceFactory
from dags.people.enrich_people_ai.spark_jobs.lib.llm_client import LiteLLMClient

JOB_NAME = "generate_ai_teva_survey_summary"
INPUT_DATABASE = "datalake_people"
INPUT_TABLE = "teva_survey_inputs"
DEFAULT_MAX_CALLS_PER_RUN = 100

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)
spark_client = SparkClient(app_name=JOB_NAME)
spark = spark_client.conn
metastore_service = MetastoreServiceFactory.create_loader_metastore_service(
    spark_client
)

_JSON_OBJECT_PATTERN = re.compile(r"\{[\s\S]*\}")

# LiteLLM JSON root keys (prompt contract) → persisted Delta column names (ai_* = model text).
_LLM_JSON_KEY_TO_COLUMN = {
    "executive_summary": "ai_executive_summary",
    "pillar_strategy_and_goals": "ai_pillar_strategy_and_goals",
    "pillar_roles_and_accountabilities": "ai_pillar_roles_and_accountabilities",
    "pillar_protocols_and_ways_of_working": "ai_pillar_protocols_and_ways_of_working",
    "pillar_trust_and_relationships": "ai_pillar_trust_and_relationships",
    "additional_comments_summary": "ai_additional_comments_summary",
}

_PILLAR_CONTEXT = (
    "Between the `` is the theoretical context you will use to complete the task "
    "and understand the pillars of analysis of the survey.\n\n"
    "`Pillars 1 and 2 (Strategy and Goal/Priorities): High performance is maintained "
    "if the team continues to have a deep understanding of and commitment to its "
    "future direction, competitive advantage, and market/product choices, and keeps "
    "daily work aligned with the most critical business goals.\n"
    "Pillar 3 (Roles, Accountabilities & Interdependencies): High-performance teams "
    "have clarity in roles, especially regarding interdependencies, and maintain a "
    "routine of review and realignment whenever context, strategy, or team members "
    "change.\n"
    "Pillar 4 (Protocols & Ways of Working): Teams transform behaviors into deeply "
    "rooted operational practices; decision-making, communication, and problem-"
    "solving processes are fast and efficient, and meetings are dynamic and action-"
    "oriented.\n"
    "Pillar 5 (Working Relationships & Trust): Teams invest in trust and resolve "
    "conflicts directly and constructively; members feel psychologically safe owning "
    "mistakes, questioning, and disagreeing openly.`"
)

_OUTPUT_INSTRUCTIONS = (
    "You are an AI People Analytics specialist. You will be provided with survey "
    "data, consisting of lists of 1-5 Likert scale answers and open-ended answers "
    "for a single team. Analyze the qualitative answers as the main focus, and use "
    "the quantitative scores only to infer overall sentiment per pillar (do not show "
    "any average grades or calculations to the final user).\n\n"
    "You must produce, in the same language as the survey answers:\n"
    "1. An executive summary stating overall team sentiment (Positive, Negative, or "
    "Neutral), the strongest pillars, and the pillars with the most significant "
    "opportunities for development, always naming pillars by their formal name.\n"
    "2. Pillars 1 and 2 (Strategy and Goals/Priorities): most cited priority themes, "
    "whether they are aligned across the team, and top blockers if any.\n"
    "3. Pillar 3 (Roles, Accountabilities & Interdependencies): most cited themes "
    "about roles and accountabilities.\n"
    "4. Pillar 4 (Protocols and Ways of Working): main suggestions and actions the "
    "team believes are necessary to operate as a high-performing team.\n"
    "5. Pillar 5 (Working Relationships and Trust): main factors harming or "
    "reinforcing trust, candor, and working relationships, if any.\n"
    "6. A synthesis of any additional open comments introducing new themes not "
    "covered above, if any.\n\n"
    "If a pillar lacks sufficient data, state plainly that there is not enough data "
    "to draw a conclusion for it; do not invent content.\n\n"
    "CRITICAL: You MUST format your entire response as a single, valid JSON object "
    "with exactly these root keys: `executive_summary`, `pillar_strategy_and_goals`, "
    "`pillar_roles_and_accountabilities`, `pillar_protocols_and_ways_of_working`, "
    "`pillar_trust_and_relationships`, `additional_comments_summary`. Each value is "
    "the full text for that section."
)


def _survey_data_payload(row: dict) -> str:
    """Build the JSON blob appended to the LiteLLM user prompt with aggregated survey fields.

    The payload includes every comma-separated Likert score list and pipe-separated
    open-text answer column from ``teva_survey_inputs`` that the model uses for analysis.
    Keys match the field names on the input row so the model can correlate scores and text.

    Args:
        row: One ``teva_survey_inputs`` record as a plain dict (typically from
            ``Row.asDict(recursive=True)``).

    Returns:
        UTF-8 JSON string (``ensure_ascii=False``) with null values preserved for
        missing optional fields.
    """
    payload = {
        "strategic_goals_clarity_scores": row.get("strategic_goals_clarity_scores"),
        "own_role_clarity_scores": row.get("own_role_clarity_scores"),
        "others_role_clarity_scores": row.get("others_role_clarity_scores"),
        "current_teamwork_scores": row.get("current_teamwork_scores"),
        "decision_making_effectiveness_scores": row.get(
            "decision_making_effectiveness_scores"
        ),
        "meeting_effectiveness_scores": row.get("meeting_effectiveness_scores"),
        "team_performance_scores": row.get("team_performance_scores"),
        "team_atmosphere_scores": row.get("team_atmosphere_scores"),
        "conflict_handling_scores": row.get("conflict_handling_scores"),
        "top_priorities_answers": row.get("top_priorities_answers"),
        "team_challenges_answers": row.get("team_challenges_answers"),
        "ideal_teamwork_answers": row.get("ideal_teamwork_answers"),
        "improvement_to_perfect_score_answers": row.get(
            "improvement_to_perfect_score_answers"
        ),
        "openness_issues_answers": row.get("openness_issues_answers"),
        "team_adjective_answers": row.get("team_adjective_answers"),
        "leader_feedback_answers": row.get("leader_feedback_answers"),
        "additional_comments_answers": row.get("additional_comments_answers"),
    }
    return json.dumps(payload, ensure_ascii=False)


def _build_teva_prompt(row: dict) -> str:
    """Assemble the full LiteLLM user message for one closed Teva survey.

    The prompt concatenates, in order: Teva pillar theory text, the few-shot
    ``reference_guide_text`` from inputs, fixed output instructions (required JSON keys),
    and the serialized survey payload from :func:`_survey_data_payload`.

    Args:
        row: One ``teva_survey_inputs`` record; must include ``reference_guide_text`` and
            the score/answer columns consumed by :func:`_survey_data_payload`.

    Returns:
        A single string passed as the user message to :meth:`LiteLLMClient.complete`.
    """
    reference_guide = row.get("reference_guide_text") or ""
    return (
        f"{_PILLAR_CONTEXT}\n\n"
        "*** BONUS: REFERENCE GUIDE FOR CLASSIFICATION ***\n"
        "Use the following examples to guide your classification of issues into "
        "pillars and sentiment. If a comment is semantically similar to one of "
        "these phrases, assign it to the corresponding pillar:\n"
        f"{reference_guide}\n\n"
        f"{_OUTPUT_INSTRUCTIONS}\n\n"
        f"{_survey_data_payload(row)}"
    )


def _extract_json_object(text: str) -> Optional[dict]:
    """Parse the first JSON object found in a LiteLLM completion string.

    The model may wrap JSON in markdown or extra prose; fenced blocks are stripped
    first, then a greedy ``{...}`` regex match is passed to ``json.loads``.

    Args:
        text: Raw assistant content from LiteLLM (may include fences or prefix text).

    Returns:
        Parsed dict when JSON is valid, otherwise ``None`` (no exception raised).
    """
    stripped = text.strip()
    if stripped.startswith("```"):
        lines = stripped.splitlines()
        if len(lines) >= 2 and lines[-1].strip() == "```":
            stripped = "\n".join(lines[1:-1]).strip()
    match = _JSON_OBJECT_PATTERN.search(stripped)
    if not match:
        return None
    try:
        return json.loads(match.group(0))
    except json.JSONDecodeError:
        return None


def _generate_summary(row: dict, client: LiteLLMClient) -> Optional[dict]:
    """Run LiteLLM once for a survey invite and shape the result for the output table.

    Calls the gateway with :func:`_build_teva_prompt`, parses JSON via
    :func:`_extract_json_object`, and copies pass-through columns from the input row.
    LiteLLM JSON root keys are mapped to ``ai_*`` STRING columns via
    :data:`_LLM_JSON_KEY_TO_COLUMN`.

    Args:
        row: One pending ``teva_survey_inputs`` row; requires ``survey_invite_id``.
        client: Configured :class:`LiteLLMClient` instance (shared across rows in ``main``).

    Returns:
        Dict matching the Spark output schema when parsing succeeds; ``None`` when
        ``survey_invite_id`` is missing or the model response is not valid JSON
        (a warning is logged in the latter case).

    Raises:
        RuntimeError: Propagated from :meth:`LiteLLMClient.complete` when the HTTP
            call fails after retries or the API returns an empty choice list.
    """
    survey_invite_id = row.get("survey_invite_id")
    if not survey_invite_id:
        return None
    raw_response = client.complete(_build_teva_prompt(row))
    parsed = _extract_json_object(raw_response)
    if parsed is None:
        logger.warning(
            "m=_generate_summary, survey_invite_id=%s, msg=could not parse JSON from LiteLLM response",
            survey_invite_id,
        )
        return None
    result = {
        "survey_invite_id": survey_invite_id,
        "survey_title": row.get("survey_title"),
        "requester_email": row.get("requester_email"),
        "answered_count": row.get("answered_count"),
        "ts_ai_summary_generated": datetime.now(timezone.utc).replace(tzinfo=None),
    }
    for json_key, column_name in _LLM_JSON_KEY_TO_COLUMN.items():
        result[column_name] = parsed.get(json_key)
    return result


def parse_args() -> dict:
    """Parse CLI arguments for the standard bietlejuice Spark job entrypoint.

    Positional args follow the DAG builder order: environment, bucket, dag_name,
    schema, table_name, partitions, load_start_date, load_end_date. Also accepts
    ``--max-calls-per-run`` and validation target overrides from
    :func:`add_validation_target_args`.

    Returns:
        Namespace values as a dict suitable for ``main`` (includes ``max_calls_per_run``).
    """
    parser = ArgumentParser()
    parser.add_argument("environment", type=str)
    parser.add_argument("bucket", type=str)
    parser.add_argument("dag_name", type=str)
    parser.add_argument("schema", type=str)
    parser.add_argument("table_name", type=str)
    parser.add_argument("partitions", type=str, nargs="*")
    parser.add_argument("load_start_date", type=str)
    parser.add_argument("load_end_date", type=str)
    parser.add_argument(
        "--max-calls-per-run",
        type=int,
        default=DEFAULT_MAX_CALLS_PER_RUN,
        help="Cost guardrail: maximum LiteLLM calls per run.",
    )
    add_validation_target_args(parser)
    return vars(parser.parse_args())


def main() -> None:
    """Entrypoint: summarize pending Teva surveys and merge into Delta.

    Resolves the enrich write target from job args, anti-joins inputs against existing
    ``survey_invite_id`` values in the target table (or limits rows on first create),
    invokes :func:`_generate_summary` for each pending row, and loads results with
    :class:`DeltaLoader` merged on ``survey_invite_id``.

    Exits early without writing when there are no pending rows or every LiteLLM call
    fails JSON parsing. Does not raise when individual rows fail parsing or when the
    HTTP client exhausts retries for a single invite; those rows are skipped and logged.
    """
    job_args = parse_args()
    db_info = DatalakeMetastoreService.get_db_info(
        job_args["environment"],
        job_args["schema"],
        job_args["bucket"],
    )
    database_name, table_name, write_location = resolve_datalake_write_target(
        prod_database=db_info["db_enrich_databricks"],
        prod_table=job_args["table_name"],
        prod_location=db_info["db_enrich_path"],
        bucket=job_args["bucket"],
        target_database=job_args.get("target_database_name"),
        target_table=job_args.get("target_table_name"),
    )
    max_calls = int(job_args.get("max_calls_per_run") or DEFAULT_MAX_CALLS_PER_RUN)

    inputs_df = spark.table(f"{INPUT_DATABASE}.{INPUT_TABLE}")
    full_table_name = f"{database_name}.{table_name}"
    if spark.catalog.tableExists(full_table_name):
        existing_df = spark.table(full_table_name)
        pending_df = inputs_df.join(
            existing_df.select("survey_invite_id"),
            on="survey_invite_id",
            how="left_anti",
        ).limit(max_calls)
    else:
        pending_df = inputs_df.limit(max_calls)

    pending_rows = [row.asDict(recursive=True) for row in pending_df.collect()]
    if not pending_rows:
        logger.info("No new closed AI Teva surveys to summarize.")
        return

    client = LiteLLMClient()
    generated = []
    for row in pending_rows:
        try:
            result = _generate_summary(row, client)
        except RuntimeError as exc:
            logger.warning(
                "m=main, survey_invite_id=%s, msg=LiteLLM call failed, skipping row, error=%s",
                row.get("survey_invite_id"),
                exc,
            )
            continue
        if result:
            generated.append(result)

    if not generated:
        logger.info("LiteLLM produced no parseable AI Teva summaries for this run.")
        return

    output_schema = StructType(
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
    output_df = spark.createDataFrame(generated, schema=output_schema)

    s3_path = f"{write_location}{table_name}"
    metastore_service.create_database(database_name)
    DeltaLoader(spark).load_table(
        table_name=full_table_name,
        path=s3_path,
        source_df=output_df,
        merge_on=["survey_invite_id"],
    )
    metastore_service.refresh_table(database_name, table_name)
    logger.info("Merged %s AI Teva survey summaries.", len(generated))


if __name__ == "__main__":
    main()
