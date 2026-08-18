"""Scorers for the tars eval harness.

``judge_query_match`` is the only scorer: a separate one-shot LLM-judge call
rates the SQL tars generated against the golden ``expected_query`` on a 1-5
scale, passing at ``judge_threshold``. Trino is mocked, so the SQL is read
from tars's own tool-call arguments (see ``_extract_generated_sql``).
"""

import re
import shlex
from pathlib import Path

from inspect_ai.model import GenerateConfig, get_model
from inspect_ai.scorer import (
    CORRECT,
    INCORRECT,
    Score,
    Scorer,
    Target,
    accuracy,
    scorer,
)
from inspect_ai.solver import TaskState

from tars_evals.retry import generate_config_kwargs

_JUDGE_PROMPT_TEMPLATE = """You are grading whether a candidate SQL query would answer a business question with the SAME INFORMATION as a known-correct reference query. Both use Trino SQL syntax.

Your job is to judge RESULT EQUIVALENCE, not textual or structural similarity. Two queries can look very different yet return the same answer, and can look similar yet return different answers. Grade the answer they would return, not how they are written.

Explicitly do NOT penalize:
- Presentation shape: the same information returned as rows vs. pivoted into columns, one row per group vs. aggregated totals, extra descriptive/context columns, different column order.
- Cosmetic differences: aliasing, formatting, capitalization, an equivalent filter written a different way (e.g. `NOT x` vs `x = FALSE`), reordered joins/predicates.

DO penalize (these change the answer):
- A different source table or metric that answers a different question.
- A filter that changes which rows are counted (added/removed/different population), including a materially different date column or time window.
- A different aggregation grain or join type that changes the numbers.

Question:
{question}

Reference (known-correct) SQL query:
{expected_sql}

Candidate SQL query to grade:
{actual_sql}

1-5 scale (in terms of the ANSWER each query returns):
5 = Same answer. Any differences are purely presentational or cosmetic (see above).
4 = Same core answer, with a minor difference unlikely to change the substantive conclusion.
3 = Addresses the same question but a difference that could materially change the result (different population/filter, different date semantics, different aggregation grain).
2 = Substantially different or only partially answers the question.
1 = Wrong table/metric, or does not answer the question.

First reason briefly, THEN give the score. Respond in exactly this format and nothing else:
REASONING: <2-3 sentences comparing the information each query would return>
SCORE: <1-5>
"""

_SCORE_PATTERN = re.compile(r"SCORE:\s*\**\s*([1-5])", re.IGNORECASE)
_REASONING_PATTERN = re.compile(
    r"REASONING:\s*(.+?)(?:\n\s*SCORE:|$)", re.IGNORECASE | re.DOTALL
)

_SQL_CODE_BLOCK_PATTERN = re.compile(r"```sql\s*\n(.*?)```", re.IGNORECASE | re.DOTALL)


def _extract_reasoning(completion: str) -> str:
    m = _REASONING_PATTERN.search(completion or "")
    return m.group(1).strip() if m else (completion or "").strip()


def _extract_flag_value(parts: list[str], flag: str) -> str | None:
    try:
        idx = parts.index(flag)
    except ValueError:
        return None
    if idx + 1 >= len(parts):
        return None
    return parts[idx + 1]


def _extract_generated_sql(state: TaskState) -> str | None:
    """Find the SQL tars decided on, or None. Prefers the most recent
    trino_connect.py --query invocation (strongest signal of the final
    answer), falling back to the last fenced ```sql block in the final text
    answer — the common case when tars answers conversationally."""
    executed_query = _extract_executed_query(state)
    if executed_query is not None:
        return executed_query
    return _extract_final_answer_sql_block(state)


def _extract_executed_query(state: TaskState) -> str | None:
    """Find the SQL text from tars's most recent trino_connect.py --query
    invocation in the transcript, or None if it never made one.
    """
    for message in reversed(state.messages):
        if getattr(message, "role", None) != "assistant":
            continue
        for call in getattr(message, "tool_calls", None) or []:
            if call.function != "run_bash":
                continue
            command = call.arguments.get("command", "")
            try:
                parts = shlex.split(command)
            except ValueError:
                continue
            if len(parts) < 2 or Path(parts[1]).name != "trino_connect.py":
                continue
            query = _extract_flag_value(parts, "--query")
            if query is not None:
                return query
    return None


def _extract_final_answer_sql_block(state: TaskState) -> str | None:
    """Find the last fenced ```sql block in tars's final answer, or None. When
    tars offers multiple variants, the last block is its final recommendation.
    """
    completion = state.output.completion or ""
    matches = _SQL_CODE_BLOCK_PATTERN.findall(completion)
    if not matches:
        return None
    return matches[-1].strip()


def _judge_config(
    reasoning_effort: str | None,
    temperature: float | None = 0.0,
) -> GenerateConfig:
    """Build the judge's per-call config.

    - With reasoning_effort: omit temperature (Claude thinking rejects a pin).
    - temperature=None: omit temperature (provider default; required for models
      like gpt-5.6-luna that reject any explicit non-default value).
    - Otherwise pin the given temperature (default 0.0 for determinism).
    The retry policy always comes from retry.py — Inspect retries forever when
    max_retries is unset, and dies on the first blip when it is pinned to 0.
    """
    kwargs: dict = dict(generate_config_kwargs())
    if reasoning_effort:
        kwargs["reasoning_effort"] = reasoning_effort
    elif temperature is not None:
        kwargs["temperature"] = temperature
    return GenerateConfig(**kwargs)


@scorer(metrics=[accuracy()])
def judge_query_match(
    judge_model: str,
    threshold: int,
    reasoning_effort: str | None = None,
    temperature: float | None = 0.0,
) -> Scorer:
    model = get_model(judge_model)
    judge_config = _judge_config(reasoning_effort, temperature=temperature)

    async def score(state: TaskState, target: Target) -> Score:
        actual_sql = _extract_generated_sql(state)
        if actual_sql is None:
            return Score(
                value=INCORRECT,
                explanation=(
                    "No SQL to grade: tars neither ran trino_connect.py --query nor "
                    "left a ```sql block in its final answer."
                ),
                metadata={
                    "judge_score": None,
                    "judge_reasoning": "tars produced no SQL to grade.",
                },
            )

        expected_sql = state.metadata["expected_query"]
        prompt = _JUDGE_PROMPT_TEMPLATE.format(
            question=state.input_text,
            expected_sql=expected_sql,
            actual_sql=actual_sql,
        )

        # judge_config pins/omits temperature and optional reasoning_effort
        # (see _judge_config).
        output = await model.generate(prompt, config=judge_config)
        completion = output.completion or ""

        # Reasoning comes before the verdict, so the judge's real SCORE is the
        # LAST "SCORE:" line — take that, not the first, so a stray "score"
        # mentioned mid-reasoning can't hijack the grade.
        matches = _SCORE_PATTERN.findall(completion)
        if not matches:
            return Score(
                value=INCORRECT,
                explanation=f"Judge model returned an unparsable response: {completion!r}",
                metadata={
                    "judge_score": None,
                    "judge_reasoning": "judge response was unparsable.",
                    # tars DID produce SQL; the judge model itself failed to
                    # return a parseable verdict. Distinct from "no SQL to
                    # grade" above so the gate doesn't mislabel a judge
                    # failure as a missing-SQL sample (see gate.py).
                    "judge_parse_error": True,
                },
            )

        judge_score = int(matches[-1])
        passed = judge_score >= threshold
        return Score(
            value=CORRECT if passed else INCORRECT,
            explanation=(
                f"Judge score: {judge_score}/5 (threshold {threshold}).\n\n"
                f"Judge response:\n{completion}\n\n"
                f"Expected SQL:\n{expected_sql}\n\n"
                f"Actual SQL:\n{actual_sql}"
            ),
            metadata={
                "judge_score": judge_score,
                "judge_reasoning": _extract_reasoning(completion),
            },
        )

    return score
