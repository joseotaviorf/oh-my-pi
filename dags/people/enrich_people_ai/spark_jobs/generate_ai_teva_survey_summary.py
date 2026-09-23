"""Run a configured People AI product and load its enrich table.

The generic entrypoint resolves a product from ``products/registry.py``. The
product supplies its input table, prompt builder, response parser, output schema,
classification column, and merge grain. Operational LiteLLM settings come from
``products/ai_products.yml``.

The DAG selects one of three processing modes: ``new_only`` processes absent
merge keys, ``unclassified`` processes absent or unclassified target rows, and
``all`` reprocesses every input row. A per-run call cap limits model cost.
"""

from __future__ import annotations

import json
import logging
import re
from argparse import ArgumentParser
from datetime import datetime, timezone
from typing import Optional

from pyspark.sql import functions as F
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
from dags.people.enrich_people_ai.spark_jobs.lib.ai_enrichment import (
    collect_generated_rows,
)
from dags.people.enrich_people_ai.spark_jobs.lib.llm_client import (
    LiteLLMClient,
    preview_llm_text,
)
from dags.people.enrich_people_ai.spark_jobs.products.registry import get_product

JOB_NAME = "generate_ai_teva_survey_summary"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)
spark_client = SparkClient(app_name=JOB_NAME)
spark = spark_client.conn
metastore_service = MetastoreServiceFactory.create_loader_metastore_service(
    spark_client
)

_PROCESSING_MODES = frozenset({"new_only", "unclassified", "all"})
_CLASSIFICATION_STATUS_COLUMN = "__ai_classification_status"

_JSON_OBJECT_PATTERN = re.compile(r"\{[\s\S]*\}")

# LiteLLM JSON root keys → Delta columns. Aliases keep the previous contract
# parseable if a leftover run still emits those names.
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
    """Build the JSON blob appended to the LiteLLM user prompt.

    Keys are the survey question titles as shown to responders so P12/P3/P4/P5
    prefixes still drive pillar attribution. Score columns become integer lists;
    open answers become string lists.

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
    """Assemble the LiteLLM user message.

    Order: pillar theory + specialist intro, few-shot ``reference_guide_text``,
    per-pillar tasks and JSON contract, English-output instruction, then the
    question-title payload.

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
            "m=_generate_summary, survey_invite_id=%s, "
            "msg=could not parse JSON from LiteLLM response, preview=%s",
            survey_invite_id,
            preview_llm_text(raw_response),
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


def _build_pending_df(inputs_df, existing_df, product, processing_mode, max_calls):
    """Select rows according to the DAG-configured reprocessing mode.

    Args:
        inputs_df: DataFrame containing the product's prepared inputs.
        existing_df: Existing target DataFrame, or ``None`` on first creation.
        product: Product contract containing merge and classification columns.
        processing_mode: One of ``new_only``, ``unclassified``, or ``all``.
        max_calls: Maximum number of rows to select for model calls.

    Returns:
        A bounded DataFrame containing only rows eligible for processing.

    Raises:
        ValueError: If the mode is unknown or ``unclassified`` lacks a
            classification column.
    """
    if processing_mode not in _PROCESSING_MODES:
        available_modes = ", ".join(sorted(_PROCESSING_MODES))
        raise ValueError(
            f"Unknown processing mode '{processing_mode}'. "
            f"Available modes: {available_modes}."
        )
    if existing_df is None or processing_mode == "all":
        return inputs_df.orderBy(
            *[F.col(key).asc_nulls_last() for key in product.merge_on]
        ).limit(max_calls)
    if processing_mode == "new_only":
        return (
            inputs_df.join(
                existing_df.select(*product.merge_on),
                on=product.merge_on,
                how="left_anti",
            )
            .orderBy(*[F.col(key).asc_nulls_last() for key in product.merge_on])
            .limit(max_calls)
        )
    if not product.classification_column:
        raise ValueError(
            f"Product '{product.key}' does not define a classification column "
            "for processing mode 'unclassified'."
        )
    existing_status_df = existing_df.select(
        *product.merge_on,
        F.col(product.classification_column).alias(_CLASSIFICATION_STATUS_COLUMN),
    )
    return (
        inputs_df.join(existing_status_df, on=product.merge_on, how="left")
        .where(
            F.col(_CLASSIFICATION_STATUS_COLUMN).isNull()
            | (F.trim(F.col(_CLASSIFICATION_STATUS_COLUMN)) == "")
        )
        .orderBy(
            F.when(F.col(_CLASSIFICATION_STATUS_COLUMN).isNull(), 0).otherwise(1),
            *[F.col(key).asc_nulls_last() for key in product.merge_on],
        )
        .drop(_CLASSIFICATION_STATUS_COLUMN)
        .limit(max_calls)
    )


def parse_args() -> dict:
    """Parse CLI arguments for the standard bietlejuice Spark job entrypoint.

    Positional args follow the DAG builder order: environment, bucket, dag_name,
    schema, table_name, partitions, load_start_date, load_end_date. Also accepts
    ``--max-calls-per-run``, ``--litellm-model``, ``--product``, and validation
    target overrides
    from :func:`add_validation_target_args`.

    Returns:
        Namespace values suitable for ``main``. CLI values override the product
        YAML configuration when supplied.
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
        default=None,
        help="Optional override for the product YAML call limit.",
    )
    parser.add_argument(
        "--litellm-model",
        type=str,
        default=None,
        help="LiteLLM chat model id (overrides LITELLM_MODEL and the client default).",
    )
    parser.add_argument(
        "--product",
        type=str,
        default="teva",
        help="AI enrichment product key registered in products/registry.py.",
    )
    parser.add_argument(
        "--processing-mode",
        choices=sorted(_PROCESSING_MODES),
        default=None,
        help=(
            "Optional override for the product YAML mode: new_only, "
            "unclassified, or all."
        ),
    )
    add_validation_target_args(parser)
    return vars(parser.parse_args())


def main() -> None:
    """Run the selected product and merge its output into Delta.

    The job selects pending inputs using the configured processing mode, invokes
    the shared AI collector, and loads results with :class:`DeltaLoader` using
    the product merge grain.

    The job exits without writing when there are no eligible rows. LiteLLM
    request failures fail the task. Unparseable model output is skipped per row;
    if no row remains valid, the task raises instead of succeeding with no table.
    """
    job_args = parse_args()
    product = get_product(job_args["product"])
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
    max_calls = int(
        job_args.get("max_calls_per_run") or product.config.max_calls_per_run
    )
    processing_mode = job_args.get("processing_mode") or product.config.processing_mode

    inputs_df = spark.table(f"{product.input_database}.{product.input_table}")
    full_table_name = f"{database_name}.{table_name}"
    if spark.catalog.tableExists(full_table_name):
        existing_df = spark.table(full_table_name)
    else:
        existing_df = None
    pending_df = _build_pending_df(
        inputs_df=inputs_df,
        existing_df=existing_df,
        product=product,
        processing_mode=processing_mode,
        max_calls=max_calls,
    )

    pending_rows = [row.asDict(recursive=True) for row in pending_df.collect()]
    if not pending_rows:
        logger.info("No new AI %s rows to summarize.", product.key)
        return

    client = LiteLLMClient(
        model=job_args.get("litellm_model") or product.config.model,
        max_retries=product.config.max_retries,
        timeout_seconds=product.config.timeout_seconds,
        max_tokens=product.config.max_tokens,
        temperature=product.config.temperature,
    )
    logger.info(
        "Using AI product=%s, model=%s, prompt_version=%s, processing_mode=%s.",
        product.key,
        client.model,
        product.config.prompt_version,
        processing_mode,
    )
    generated = collect_generated_rows(
        pending_rows=pending_rows,
        client=client,
        product=product,
        logger=logger,
    )
    output_df = spark.createDataFrame(
        generated,
        schema=product.build_output_schema(),
    )

    s3_path = f"{write_location}{table_name}"
    metastore_service.create_database(database_name)
    DeltaLoader(spark).load_table(
        table_name=full_table_name,
        path=s3_path,
        source_df=output_df,
        merge_on=product.merge_on,
    )
    metastore_service.refresh_table(database_name, table_name)
    logger.info("Merged %s AI %s rows.", len(generated), product.key)


if __name__ == "__main__":
    main()
