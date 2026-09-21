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
from dags.people.enrich_people_ai.spark_jobs.lib import (
    teva_legacy_prompt as teva_prompt,
)
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

# Notebook ``ai_query`` JSON root keys → Delta columns. Aliases keep the previous
# LiteLLM contract parseable if a leftover run still emits those names.
_LLM_JSON_KEY_TO_COLUMN = {
    "executive_summary": "ai_executive_summary",
    "pillar_1_2_strategy_goals": "ai_pillar_strategy_and_goals",
    "pillar_3_roles": "ai_pillar_roles_and_accountabilities",
    "pillar_4_protocols": "ai_pillar_protocols_and_ways_of_working",
    "pillar_5_trust": "ai_pillar_trust_and_relationships",
    "additional_comments": "ai_additional_comments_summary",
    "pillar_strategy_and_goals": "ai_pillar_strategy_and_goals",
    "pillar_roles_and_accountabilities": "ai_pillar_roles_and_accountabilities",
    "pillar_protocols_and_ways_of_working": "ai_pillar_protocols_and_ways_of_working",
    "pillar_trust_and_relationships": "ai_pillar_trust_and_relationships",
    "additional_comments_summary": "ai_additional_comments_summary",
}


def _split_score_list(value: Optional[str]) -> Optional[list]:
    """Turn a comma-separated Likert string into a list (notebook ``COLLECT_LIST``)."""
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
    """Turn pipe-separated open answers into a list (notebook ``COLLECT_LIST``)."""
    if not value:
        return None
    parts = [part.strip() for part in str(value).split(" | ") if part.strip()]
    return parts or None


def _survey_data_payload(row: dict) -> str:
    """Build the JSON blob appended to the LiteLLM user prompt.

    Keys are the survey question titles from the notebook ``ia_input`` STRUCT so
    P12/P3/P4/P5 prefixes still drive pillar attribution. Score columns become
    integer lists; open answers become string lists.

    Args:
        row: One ``teva_survey_inputs`` record as a plain dict (typically from
            ``Row.asDict(recursive=True)``).

    Returns:
        UTF-8 JSON string (``ensure_ascii=False``) with null values preserved for
        missing optional fields.
    """
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


def _build_teva_prompt(row: dict) -> str:
    """Assemble the LiteLLM user message matching notebook ``ai_query`` CONCAT order.

    Order: pillar theory + specialist intro, few-shot ``reference_guide_text``,
    per-pillar tasks and JSON contract, English-output stand-in for
    ``ai_translate``, then the question-title payload.

    Args:
        row: One ``teva_survey_inputs`` record; must include ``reference_guide_text``
            and the score/answer columns consumed by :func:`_survey_data_payload`.

    Returns:
        A single string passed as the user message to :meth:`LiteLLMClient.complete`.
    """
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
    """Flatten a JSON section to STRING, including nested objects from older models."""
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
    for column_name in _LLM_JSON_KEY_TO_COLUMN.values():
        result.setdefault(column_name, None)
    for json_key, column_name in _LLM_JSON_KEY_TO_COLUMN.items():
        if result.get(column_name) is not None:
            continue
        if json_key not in parsed:
            continue
        result[column_name] = _section_text(parsed.get(json_key))
    return result


def _collect_generated_summaries(pending_rows: list, client: LiteLLMClient) -> list:
    """Call LiteLLM for each pending invite and keep parseable summaries.

    LiteLLM HTTP/runtime failures propagate so the Spark job fails instead of
    writing nothing and exiting 0. Unparseable model text is skipped per row;
    if every pending row is skipped, this raises so Airflow still fails.

    Args:
        pending_rows: Input dicts, typically from ``teva_survey_inputs``.
        client: Shared :class:`LiteLLMClient` instance.

    Returns:
        Non-empty list of output rows matching the Spark schema.

    Raises:
        RuntimeError: From :func:`_generate_summary` / :meth:`LiteLLMClient.complete`,
            or when no pending row produced a parseable summary.
    """
    generated = []
    for row in pending_rows:
        result = _generate_summary(row, client)
        if result:
            generated.append(result)
    if not generated:
        raise RuntimeError(
            "LiteLLM produced no parseable AI Teva summaries for this run."
        )
    return generated


def parse_args() -> dict:
    """Parse CLI arguments for the standard bietlejuice Spark job entrypoint.

    Positional args follow the DAG builder order: environment, bucket, dag_name,
    schema, table_name, partitions, load_start_date, load_end_date. Also accepts
    ``--max-calls-per-run``, ``--litellm-model``, and validation target overrides
    from :func:`add_validation_target_args`.

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
    parser.add_argument(
        "--litellm-model",
        type=str,
        default=None,
        help="LiteLLM chat model id (overrides LITELLM_MODEL and the client default).",
    )
    add_validation_target_args(parser)
    return vars(parser.parse_args())


def main() -> None:
    """Entrypoint: summarize pending Teva surveys and merge into Delta.

    Resolves the enrich write target from job args, anti-joins inputs against existing
    ``survey_invite_id`` values in the target table (or limits rows on first create),
    invokes :func:`_collect_generated_summaries` for each pending row, and loads
    results with :class:`DeltaLoader` merged on ``survey_invite_id``.

    Exits without writing when there are no pending rows. LiteLLM HTTP failures
    fail the job. Unparseable model output is skipped per row; if that leaves
    nothing to write, the job raises instead of succeeding with no table.
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

    client = LiteLLMClient(model=job_args.get("litellm_model"))
    generated = _collect_generated_summaries(pending_rows, client)

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
