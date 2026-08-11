from pathlib import Path

import pytest
from tars_evals.config import load_config


def test_load_config_reads_all_fields(tmp_path):
    config_path = tmp_path / "config.yaml"
    config_path.write_text(
        "tars_model: openai/vertex_ai/claude-sonnet-4-6@default\n"
        "judge_model: openai/vertex_ai/claude-sonnet-4-6@default\n"
        "judge_reasoning_effort: low\n"
        "judge_threshold: 4\n"
    )

    config = load_config(config_path)

    assert config.tars_model == "openai/vertex_ai/claude-sonnet-4-6@default"
    assert config.judge_model == "openai/vertex_ai/claude-sonnet-4-6@default"
    assert config.judge_reasoning_effort == "low"
    assert config.judge_threshold == 4


def test_load_config_reasoning_effort_defaults_to_none_when_absent(tmp_path):
    config_path = tmp_path / "config.yaml"
    config_path.write_text(
        "tars_model: openai/vertex_ai/claude-sonnet-4-6@default\n"
        "judge_model: openai/vertex_ai/claude-haiku-4-5@20251001\n"
        "judge_threshold: 4\n"
    )

    config = load_config(config_path)

    assert config.judge_reasoning_effort is None


def test_load_config_blank_reasoning_effort_is_none(tmp_path):
    config_path = tmp_path / "config.yaml"
    config_path.write_text(
        "tars_model: openai/vertex_ai/claude-sonnet-4-6@default\n"
        "judge_model: openai/vertex_ai/claude-haiku-4-5@20251001\n"
        "judge_reasoning_effort: ''\n"
        "judge_threshold: 4\n"
    )

    config = load_config(config_path)

    assert config.judge_reasoning_effort is None


def test_load_config_coerces_threshold_to_int(tmp_path):
    config_path = tmp_path / "config.yaml"
    config_path.write_text(
        "tars_model: openai/vertex_ai/claude-sonnet-4-6@default\n"
        "judge_model: openai/vertex_ai/claude-haiku-4-5@20251001\n"
        "judge_threshold: '4'\n"
    )

    config = load_config(config_path)

    assert config.judge_threshold == 4
    assert isinstance(config.judge_threshold, int)


def test_load_config_missing_field_raises_key_error(tmp_path):
    config_path = tmp_path / "config.yaml"
    config_path.write_text("tars_model: openai/vertex_ai/claude-sonnet-4-6@default\n")

    with pytest.raises(KeyError):
        load_config(config_path)


def test_both_models_use_compatible_provider():
    cfg = load_config(Path(__file__).resolve().parents[1] / "config.yaml")
    assert cfg.tars_model.startswith("openai-api/litellm/")
    assert cfg.judge_model.startswith("openai-api/litellm/")


def test_committed_config_uses_luna_judge():
    cfg = load_config(Path(__file__).resolve().parents[1] / "config.yaml")
    assert cfg.judge_model == "openai-api/litellm/gpt-5.6-luna"
    # Luna rejects explicit temperature=0; omit so the provider default applies.
    assert cfg.judge_temperature is None


def test_load_config_judge_temperature_defaults_to_zero(tmp_path: Path):
    config_path = tmp_path / "config.yaml"
    config_path.write_text(
        "tars_model: m\njudge_model: j\njudge_threshold: 4\n",
        encoding="utf-8",
    )

    assert load_config(config_path).judge_temperature == 0.0


def test_load_config_blank_judge_temperature_means_omit(tmp_path: Path):
    config_path = tmp_path / "config.yaml"
    config_path.write_text(
        "tars_model: m\njudge_model: j\njudge_threshold: 4\njudge_temperature:\n",
        encoding="utf-8",
    )

    assert load_config(config_path).judge_temperature is None


def test_gate_pass_rate_default_and_override(tmp_path: Path):
    base = "tars_model: m\njudge_model: j\njudge_threshold: 4\n"
    p1 = tmp_path / "c1.yaml"
    p1.write_text(base)
    assert load_config(p1).gate_pass_rate == 0.9

    p2 = tmp_path / "c2.yaml"
    p2.write_text(base + "gate_pass_rate: 0.8\n")
    assert load_config(p2).gate_pass_rate == 0.8
