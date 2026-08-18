import asyncio

from inspect_ai.model import ChatMessageAssistant
from inspect_ai.scorer import CORRECT, INCORRECT
from inspect_ai.tool import ToolCall
from tars_evals.retry import DEFAULT_MAX_RETRIES, DEFAULT_REQUEST_TIMEOUT
from tars_evals.scorer import _extract_generated_sql, judge_query_match


def _assistant_run_bash(command: str) -> ChatMessageAssistant:
    return ChatMessageAssistant(
        content="",
        tool_calls=[
            ToolCall(id="1", function="run_bash", arguments={"command": command})
        ],
    )


def test_extract_generated_sql_finds_query_flag():
    state = _FakeState(
        [
            _assistant_run_bash(
                'python3 /some/dir/trino_connect.py --query "SELECT 1"'
            ),
        ]
    )
    assert _extract_generated_sql(state) == "SELECT 1"


def test_extract_generated_sql_uses_most_recent_call():
    state = _FakeState(
        [
            _assistant_run_bash(
                'python3 /some/dir/trino_connect.py --query "SELECT 1"'
            ),
            _assistant_run_bash(
                'python3 /some/dir/trino_connect.py --query "SELECT 2"'
            ),
        ]
    )
    assert _extract_generated_sql(state) == "SELECT 2"


def test_extract_generated_sql_ignores_non_query_calls():
    state = _FakeState(
        [
            _assistant_run_bash("python3 /some/dir/trino_connect.py --check-token"),
        ]
    )
    assert _extract_generated_sql(state) is None


def test_extract_generated_sql_none_when_no_trino_call():
    state = _FakeState(
        [
            _assistant_run_bash("python3 /some/dir/datahub_connect.py probe"),
        ]
    )
    assert _extract_generated_sql(state) is None


def test_extract_generated_sql_falls_back_to_final_answer_sql_block():
    state = _FakeState(
        [
            _assistant_run_bash("python3 /some/dir/datahub_connect.py probe"),
        ]
    )
    state.output = _FakeModelOutput(
        "Here's the query:\n\n```sql\nSELECT COUNT(*) FROM offboarding\n```\n\nWant me to run it?"
    )
    assert _extract_generated_sql(state) == "SELECT COUNT(*) FROM offboarding"


def test_extract_generated_sql_prefers_trino_query_over_final_answer_block():
    state = _FakeState(
        [
            _assistant_run_bash(
                'python3 /some/dir/trino_connect.py --query "SELECT 1"'
            ),
        ]
    )
    state.output = _FakeModelOutput("```sql\nSELECT 2\n```")
    assert _extract_generated_sql(state) == "SELECT 1"


def test_extract_generated_sql_uses_last_sql_block_when_multiple_present():
    state = _FakeState(
        [
            _assistant_run_bash("python3 /some/dir/datahub_connect.py probe"),
        ]
    )
    state.output = _FakeModelOutput(
        "Option A:\n```sql\nSELECT 1\n```\n\nOption B (recommended):\n```sql\nSELECT 2\n```"
    )
    assert _extract_generated_sql(state) == "SELECT 2"


def test_extract_generated_sql_none_when_no_query_and_no_final_answer_sql_block():
    state = _FakeState(
        [
            _assistant_run_bash("python3 /some/dir/datahub_connect.py probe"),
        ]
    )
    state.output = _FakeModelOutput(
        "I couldn't find enough schema info to write this query."
    )
    assert _extract_generated_sql(state) is None


class _FakeState:
    def __init__(self, messages):
        self.messages = messages
        self.metadata = {}
        self.input_text = "What is the answer?"
        self.output = _FakeModelOutput("")


class _FakeModelOutput:
    def __init__(self, completion):
        self.completion = completion


class _FakeModel:
    def __init__(self, completion):
        self._completion = completion
        self.requested_prompt = None

    async def generate(self, input, config=None):
        self.requested_prompt = input
        self.requested_config = config
        return _FakeModelOutput(self._completion)


def _state_with_sql(actual_sql: str, expected_sql: str = "SELECT 1") -> _FakeState:
    state = _FakeState(
        [
            _assistant_run_bash(
                f'python3 /some/dir/trino_connect.py --query "{actual_sql}"'
            ),
        ]
    )
    state.metadata = {"expected_query": expected_sql}
    return state


def test_judge_query_match_passes_at_or_above_threshold(monkeypatch):
    fake_model = _FakeModel("SCORE: 5\nREASON: equivalent query")
    monkeypatch.setattr("tars_evals.scorer.get_model", lambda *a, **k: fake_model)

    scorer_fn = judge_query_match(judge_model="openai/fake-judge", threshold=4)
    score = asyncio.run(scorer_fn(_state_with_sql("SELECT 1"), target=None))

    assert score.value == CORRECT
    assert "5" in score.explanation


def test_judge_query_match_fails_below_threshold(monkeypatch):
    fake_model = _FakeModel("SCORE: 2\nREASON: wrong table")
    monkeypatch.setattr("tars_evals.scorer.get_model", lambda *a, **k: fake_model)

    scorer_fn = judge_query_match(judge_model="openai/fake-judge", threshold=4)
    score = asyncio.run(scorer_fn(_state_with_sql("SELECT 2"), target=None))

    assert score.value == INCORRECT


def test_judge_query_match_uses_configured_model(monkeypatch):
    fake_model = _FakeModel("SCORE: 5\nREASON: ok")
    captured = {}

    def fake_get_model(model_id, **kwargs):
        captured["model_id"] = model_id
        captured["kwargs"] = kwargs
        return fake_model

    monkeypatch.setattr("tars_evals.scorer.get_model", fake_get_model)

    scorer_fn = judge_query_match(
        judge_model="openai-api/litellm/vertex_ai/claude-haiku-4-5@20251001",
        threshold=4,
    )
    asyncio.run(scorer_fn(_state_with_sql("SELECT 1"), target=None))

    assert (
        captured["model_id"] == "openai-api/litellm/vertex_ai/claude-haiku-4-5@20251001"
    )
    assert "responses_api" not in captured["kwargs"]


def test_judge_query_match_incorrect_when_no_sql_generated(monkeypatch):
    fake_model = _FakeModel("SCORE: 5\nREASON: n/a")
    monkeypatch.setattr("tars_evals.scorer.get_model", lambda *a, **k: fake_model)

    state = _FakeState(
        [_assistant_run_bash("python3 /some/dir/datahub_connect.py probe")]
    )
    state.metadata = {"expected_query": "SELECT 1"}

    scorer_fn = judge_query_match(judge_model="openai/fake-judge", threshold=4)
    score = asyncio.run(scorer_fn(state, target=None))

    assert score.value == INCORRECT
    assert fake_model.requested_prompt is None  # judge never called — no SQL to grade


def test_judge_query_match_incorrect_on_unparsable_judge_response(monkeypatch):
    fake_model = _FakeModel("I refuse to answer in the requested format.")
    monkeypatch.setattr("tars_evals.scorer.get_model", lambda *a, **k: fake_model)

    scorer_fn = judge_query_match(judge_model="openai/fake-judge", threshold=4)
    score = asyncio.run(scorer_fn(_state_with_sql("SELECT 1"), target=None))

    assert score.value == INCORRECT
    # tars DID produce SQL — the judge itself failed to parse. Must be
    # distinguishable from the "no SQL to grade" case (see gate.py).
    assert score.metadata["judge_parse_error"] is True


def test_judge_query_match_parses_lowercase_and_markdown_bold_score(monkeypatch):
    fake_model = _FakeModel("**Score:** 4\nREASON: close enough")
    monkeypatch.setattr("tars_evals.scorer.get_model", lambda *a, **k: fake_model)

    scorer_fn = judge_query_match(judge_model="openai/fake-judge", threshold=4)
    score = asyncio.run(scorer_fn(_state_with_sql("SELECT 1"), target=None))

    assert score.value == CORRECT


def test_judge_query_match_includes_question_and_both_queries_in_prompt(monkeypatch):
    fake_model = _FakeModel("SCORE: 5\nREASON: ok")
    monkeypatch.setattr("tars_evals.scorer.get_model", lambda *a, **k: fake_model)

    scorer_fn = judge_query_match(judge_model="openai/fake-judge", threshold=4)
    state = _state_with_sql("SELECT 1", expected_sql="SELECT 2")
    asyncio.run(scorer_fn(state, target=None))

    assert "What is the answer?" in fake_model.requested_prompt
    assert "SELECT 1" in fake_model.requested_prompt
    assert "SELECT 2" in fake_model.requested_prompt


def test_judge_query_match_passes_when_score_exactly_equals_threshold(monkeypatch):
    fake_model = _FakeModel("SCORE: 4\nREASON: minor cosmetic differences")
    monkeypatch.setattr("tars_evals.scorer.get_model", lambda *a, **k: fake_model)

    scorer_fn = judge_query_match(judge_model="openai/fake-judge", threshold=4)
    score = asyncio.run(scorer_fn(_state_with_sql("SELECT 1"), target=None))

    assert score.value == CORRECT


def test_judge_query_match_parses_reasoning_before_score(monkeypatch):
    fake_model = _FakeModel(
        "REASONING: Same table and population, only pivoted differently.\nSCORE: 5"
    )
    monkeypatch.setattr("tars_evals.scorer.get_model", lambda *a, **k: fake_model)

    scorer_fn = judge_query_match(judge_model="openai/fake-judge", threshold=4)
    score = asyncio.run(scorer_fn(_state_with_sql("SELECT 1"), target=None))

    assert score.value == CORRECT


def test_judge_query_match_uses_last_score_when_reasoning_mentions_a_score(monkeypatch):
    fake_model = _FakeModel(
        "REASONING: A stricter rubric might give SCORE: 2 here, but the "
        "queries are equivalent.\nSCORE: 5"
    )
    monkeypatch.setattr("tars_evals.scorer.get_model", lambda *a, **k: fake_model)

    scorer_fn = judge_query_match(judge_model="openai/fake-judge", threshold=4)
    score = asyncio.run(scorer_fn(_state_with_sql("SELECT 1"), target=None))

    assert score.value == CORRECT


def test_judge_query_match_grades_judge_at_temperature_zero_without_reasoning(
    monkeypatch,
):
    fake_model = _FakeModel("REASONING: equivalent.\nSCORE: 5")
    monkeypatch.setattr("tars_evals.scorer.get_model", lambda *a, **k: fake_model)

    scorer_fn = judge_query_match(judge_model="openai/fake-judge", threshold=4)
    asyncio.run(scorer_fn(_state_with_sql("SELECT 1"), target=None))

    assert fake_model.requested_config is not None
    assert fake_model.requested_config.temperature == 0.0
    assert fake_model.requested_config.reasoning_effort is None


def test_judge_query_match_passes_reasoning_effort_without_pinning_temperature(
    monkeypatch,
):
    fake_model = _FakeModel("REASONING: equivalent.\nSCORE: 5")
    monkeypatch.setattr("tars_evals.scorer.get_model", lambda *a, **k: fake_model)

    scorer_fn = judge_query_match(
        judge_model="openai/fake-judge", threshold=4, reasoning_effort="low"
    )
    asyncio.run(scorer_fn(_state_with_sql("SELECT 1"), target=None))

    assert fake_model.requested_config is not None
    assert fake_model.requested_config.reasoning_effort == "low"
    # Claude thinking can't be combined with a pinned temperature=0.
    assert fake_model.requested_config.temperature is None
    assert fake_model.requested_config.max_retries == DEFAULT_MAX_RETRIES


def test_judge_config_uses_shared_retry_policy_without_reasoning(monkeypatch):
    fake_model = _FakeModel("REASONING: equivalent.\nSCORE: 5")
    monkeypatch.setattr("tars_evals.scorer.get_model", lambda *a, **k: fake_model)

    scorer_fn = judge_query_match(judge_model="openai/fake-judge", threshold=4)
    asyncio.run(scorer_fn(_state_with_sql("SELECT 1"), target=None))

    assert fake_model.requested_config is not None
    assert fake_model.requested_config.max_retries == DEFAULT_MAX_RETRIES
    assert fake_model.requested_config.timeout == DEFAULT_REQUEST_TIMEOUT
    assert fake_model.requested_config.temperature == 0.0


def test_judge_query_match_omits_temperature_when_none(monkeypatch):
    """Models like gpt-5.6-luna reject explicit temperature; omit it entirely."""
    fake_model = _FakeModel("REASONING: equivalent.\nSCORE: 5")
    monkeypatch.setattr("tars_evals.scorer.get_model", lambda *a, **k: fake_model)

    scorer_fn = judge_query_match(
        judge_model="openai-api/litellm/gpt-5.6-luna",
        threshold=4,
        temperature=None,
    )
    asyncio.run(scorer_fn(_state_with_sql("SELECT 1"), target=None))

    assert fake_model.requested_config is not None
    assert fake_model.requested_config.temperature is None
    assert fake_model.requested_config.max_retries == DEFAULT_MAX_RETRIES
    assert "temperature" not in fake_model.requested_config.model_fields_set


def test_judge_query_match_preserves_explicit_temperature(monkeypatch):
    fake_model = _FakeModel("REASONING: equivalent.\nSCORE: 5")
    monkeypatch.setattr("tars_evals.scorer.get_model", lambda *a, **k: fake_model)

    scorer_fn = judge_query_match(
        judge_model="openai/fake-judge", threshold=4, temperature=0.0
    )
    asyncio.run(scorer_fn(_state_with_sql("SELECT 1"), target=None))

    assert fake_model.requested_config is not None
    assert fake_model.requested_config.temperature == 0.0
    assert "temperature" in fake_model.requested_config.model_fields_set


def test_score_metadata_carries_judge_score_and_reasoning(monkeypatch):
    fake_model = _FakeModel("REASONING: same answer.\nSCORE: 5")
    monkeypatch.setattr("tars_evals.scorer.get_model", lambda *a, **k: fake_model)

    scorer_fn = judge_query_match(judge_model="openai/fake-judge", threshold=4)
    score = asyncio.run(scorer_fn(_state_with_sql("SELECT 1"), target=None))

    assert score.metadata["judge_score"] == 5
    assert "same answer" in score.metadata["judge_reasoning"].lower()


def test_score_metadata_none_when_no_sql(monkeypatch):
    fake_model = _FakeModel("SCORE: 5\nREASON: n/a")
    monkeypatch.setattr("tars_evals.scorer.get_model", lambda *a, **k: fake_model)

    state = _FakeState([])  # no tool calls + empty completion → no SQL
    state.metadata = {"expected_query": "SELECT 1"}

    scorer_fn = judge_query_match(judge_model="openai/fake-judge", threshold=4)
    score = asyncio.run(scorer_fn(state, target=None))

    assert score.metadata["judge_score"] is None
