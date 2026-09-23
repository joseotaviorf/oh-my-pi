"""Shared execution primitives for People AI enrichment products."""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Callable, Optional

from pyspark.sql.types import StructType

from dags.people.enrich_people_ai.spark_jobs.lib.llm_client import (
    LiteLLMClient,
    preview_llm_text,
)

PromptBuilder = Callable[[dict], str]
ResponseParser = Callable[[dict, str, datetime], Optional[dict]]
OutputSchemaBuilder = Callable[[], StructType]


@dataclass(frozen=True)
class AIProductConfig:
    """Operational LiteLLM settings loaded from the product YAML.

    Attributes:
        model: LiteLLM model ID, including its provider prefix.
        max_calls_per_run: Maximum model calls allowed in one Spark task.
        prompt_version: Version label for the prompt contract used by the product.
        processing_mode: Default input-selection mode for the product.
        temperature: Sampling temperature sent to LiteLLM.
        max_tokens: Maximum response tokens sent to LiteLLM.
        timeout_seconds: Per-request timeout.
        max_retries: Maximum attempts for transient request failures.
        max_concurrency: Maximum number of LiteLLM requests made concurrently.
    """

    model: str
    max_calls_per_run: int
    prompt_version: str
    processing_mode: str
    temperature: float
    max_tokens: int
    timeout_seconds: int
    max_retries: int
    max_concurrency: int


@dataclass(frozen=True)
class AIProduct:
    """Configuration and product-specific behavior for one AI output table.

    Attributes:
        key: Stable product key passed by the DAG declaration.
        input_database: Database containing prepared product inputs.
        input_table: Table containing one input row per product grain.
        merge_on: Columns that identify one output row.
        build_prompt: Product-specific prompt builder.
        parse_response: Product-specific response parser and output shaper.
        build_output_schema: Builder for the product's Spark output schema.
        config: Operational settings loaded from ``ai_products.yml``.
        classification_column: Output column used by ``unclassified`` mode.
    """

    key: str
    input_database: str
    input_table: str
    merge_on: list
    build_prompt: PromptBuilder
    parse_response: ResponseParser
    build_output_schema: OutputSchemaBuilder
    config: AIProductConfig
    classification_column: Optional[str] = None


def collect_generated_rows(
    pending_rows: list,
    client: LiteLLMClient,
    product: AIProduct,
    logger,
) -> list:
    """Generate and parse rows for one product.

    Transport failures are propagated so the Spark task fails closed. Invalid model
    responses are skipped individually; a run with no valid responses fails instead
    of succeeding while writing no data.

    Args:
        pending_rows: Input records selected by the configured processing mode.
        client: LiteLLM-compatible client used for model calls.
        product: Product contract used to build prompts and parse responses.
        logger: Logger receiving invalid-row and invalid-response warnings.

    Returns:
        Parsed output records ready for Spark DataFrame creation.

    Raises:
        RuntimeError: If no selected row produces a parseable model response.
    """
    valid_rows = []
    for row in pending_rows:
        row_key = "|".join(str(row.get(key) or "<missing>") for key in product.merge_on)
        missing_merge_keys = [
            key for key in product.merge_on if row.get(key) in (None, "")
        ]
        if missing_merge_keys:
            logger.warning(
                "m=collect_generated_rows, product=%s, row_key=%s, "
                "msg=skipping row with missing merge keys=%s",
                product.key,
                row_key,
                missing_merge_keys,
            )
            continue

        valid_rows.append((row, row_key))

    def generate_row(row_and_key):
        row, row_key = row_and_key
        raw_response = client.complete(product.build_prompt(row))
        result = product.parse_response(
            row,
            raw_response,
            datetime.now(timezone.utc).replace(tzinfo=None),
        )
        return row_key, result, raw_response

    generated = []
    max_workers = min(product.config.max_concurrency, len(valid_rows))
    if max_workers:
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            for row_key, result, raw_response in executor.map(generate_row, valid_rows):
                if result:
                    generated.append(result)
                    continue
                logger.warning(
                    "m=collect_generated_rows, product=%s, row_key=%s, "
                    "msg=could not parse model response, response_preview=%s",
                    product.key,
                    row_key,
                    preview_llm_text(raw_response),
                )
    if not generated:
        raise RuntimeError(
            f"AI model produced no parseable {product.key} rows for this run."
        )
    return generated
