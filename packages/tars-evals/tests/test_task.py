"""Tests for the shared Inspect Task factory ``make_tars_eval_task``."""

from pathlib import Path

import pytest
from inspect_ai.dataset import Sample
from tars_evals.config import EvalConfig
from tars_evals.retry import DEFAULT_MAX_RETRIES, DEFAULT_REQUEST_TIMEOUT


@pytest.fixture
def skill_dir(tmp_path: Path) -> Path:
    skill = tmp_path / "skill"
    skill.mkdir()
    (skill / "SKILL.md").write_text("# tars skill\nUse tools.\n", encoding="utf-8")
    (skill / "scripts").mkdir()
    return skill


@pytest.fixture
def eval_config() -> EvalConfig:
    return EvalConfig(
        tars_model="openai-api/litellm/vertex_ai/claude-sonnet-4-6@default",
        judge_model="openai-api/litellm/vertex_ai/claude-sonnet-4-6@default",
        judge_threshold=4,
        judge_reasoning_effort="low",
        gate_pass_rate=0.9,
    )


@pytest.fixture
def samples() -> list[Sample]:
    return [
        Sample(
            input="How many turnovers?",
            target="SELECT 1",
            id="turnover_q1",
            metadata={"expected_query": "SELECT 1", "dataset": "turnover"},
        ),
        Sample(
            input="NPS last month?",
            target="SELECT 2",
            id="nps_q1",
            metadata={"expected_query": "SELECT 2", "dataset": "nps_fr"},
        ),
    ]


def test_make_tars_eval_task_preserves_samples_and_limits(
    samples, eval_config, skill_dir
):
    from tars_evals.task import make_tars_eval_task

    task = make_tars_eval_task(samples, config=eval_config, skill_dir=skill_dir)

    assert len(task.dataset) == 2
    assert [s.id for s in task.dataset] == ["turnover_q1", "nps_q1"]
    assert task.dataset[0].input == "How many turnovers?"
    assert task.dataset[1].metadata["dataset"] == "nps_fr"
    assert task.message_limit == 80
    assert task.config.max_tool_output == 200_000
    assert task.config.max_retries == DEFAULT_MAX_RETRIES
    assert task.config.timeout == DEFAULT_REQUEST_TIMEOUT
    # Task-level config must stay temperature-free (judge uses reasoning).
    assert task.config.temperature is None


def test_subject_model_uses_bounded_retry_policy(eval_config):
    """max_retries=0 would end a sample on the first connection blip and count
    it against the gate as if the SQL were wrong (see retry.py)."""
    from tars_evals.task import _subject_model

    model = _subject_model(eval_config)

    assert model.config.max_retries == DEFAULT_MAX_RETRIES
    assert model.config.timeout == DEFAULT_REQUEST_TIMEOUT
    assert model.config.temperature == 0.0


def test_retry_policy_is_env_overridable(eval_config, monkeypatch):
    from tars_evals.task import _subject_model

    monkeypatch.setenv("TARS_EVAL_MAX_RETRIES", "2")
    monkeypatch.setenv("TARS_EVAL_REQUEST_TIMEOUT", "0")

    model = _subject_model(eval_config)

    assert model.config.max_retries == 2
    # 0 means "no wall-clock ceiling" — the key must be omitted, not zeroed.
    assert model.config.timeout is None


def test_make_tars_eval_task_wires_subject_model_and_scorer(
    samples, eval_config, skill_dir
):
    from tars_evals.task import make_tars_eval_task

    task = make_tars_eval_task(samples, config=eval_config, skill_dir=skill_dir)

    assert task.model is not None
    assert type(task.model.api).__name__ == "OpenAICompatibleAPI"
    assert task.model.config.temperature == 0.0
    assert task.scorer is not None
    assert len(task.scorer) == 1
    assert callable(task.scorer[0])
    # Inspect wraps the 3 verbatim system messages + react agent into a Chain.
    assert type(task.solver).__name__ == "Chain"
    assert len(task.solver) == 4


def test_make_tars_eval_task_wires_judge_query_match_from_config(
    samples, skill_dir, monkeypatch
):
    """Factory must pass judge fields from EvalConfig into judge_query_match."""
    import tars_evals.task as task_mod
    from tars_evals.task import make_tars_eval_task

    config = EvalConfig(
        tars_model="openai-api/litellm/vertex_ai/claude-sonnet-4-6@default",
        judge_model="openai-api/litellm/vertex_ai/claude-haiku-4-5@20251001",
        judge_threshold=5,
        judge_reasoning_effort="medium",
        judge_temperature=0.0,
        gate_pass_rate=0.9,
    )
    captured: dict = {}
    real_judge = task_mod.judge_query_match

    def spy_judge_query_match(
        judge_model, threshold, reasoning_effort=None, temperature=0.0
    ):
        captured["judge_model"] = judge_model
        captured["threshold"] = threshold
        captured["reasoning_effort"] = reasoning_effort
        captured["temperature"] = temperature
        return real_judge(
            judge_model,
            threshold,
            reasoning_effort=reasoning_effort,
            temperature=temperature,
        )

    monkeypatch.setattr(task_mod, "judge_query_match", spy_judge_query_match)

    make_tars_eval_task(samples, config=config, skill_dir=skill_dir)

    assert captured == {
        "judge_model": "openai-api/litellm/vertex_ai/claude-haiku-4-5@20251001",
        "threshold": 5,
        "reasoning_effort": "medium",
        "temperature": 0.0,
    }


def test_make_tars_eval_task_wires_omitted_luna_judge_temperature(
    samples, skill_dir, monkeypatch
):
    import tars_evals.task as task_mod
    from tars_evals.task import make_tars_eval_task

    config = EvalConfig(
        tars_model="openai-api/litellm/vertex_ai/claude-sonnet-4-6@default",
        judge_model="openai-api/litellm/gpt-5.6-luna",
        judge_threshold=4,
        judge_reasoning_effort=None,
        judge_temperature=None,
        gate_pass_rate=0.9,
    )
    captured: dict = {}
    real_judge = task_mod.judge_query_match

    def spy_judge_query_match(
        judge_model, threshold, reasoning_effort=None, temperature=0.0
    ):
        captured["temperature"] = temperature
        return real_judge(
            judge_model,
            threshold,
            reasoning_effort=reasoning_effort,
            temperature=temperature,
        )

    monkeypatch.setattr(task_mod, "judge_query_match", spy_judge_query_match)

    make_tars_eval_task(samples, config=config, skill_dir=skill_dir)

    assert captured["temperature"] is None


def test_make_tars_eval_task_loads_config_from_path(samples, skill_dir, tmp_path: Path):
    from tars_evals.task import make_tars_eval_task

    config_path = tmp_path / "config.yaml"
    config_path.write_text(
        "tars_model: openai-api/litellm/vertex_ai/claude-sonnet-4-6@default\n"
        "judge_model: openai-api/litellm/vertex_ai/claude-sonnet-4-6@default\n"
        "judge_threshold: 4\n"
        "judge_reasoning_effort: low\n",
        encoding="utf-8",
    )

    task = make_tars_eval_task(samples, config_path=config_path, skill_dir=skill_dir)

    assert len(task.dataset) == 2
    assert task.message_limit == 80
    assert task.config.max_tool_output == 200_000
    assert type(task.model.api).__name__ == "OpenAICompatibleAPI"
