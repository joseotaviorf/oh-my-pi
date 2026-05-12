import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[6]))

from scripts.ci_cd.source_layer_validation.layer_policy_matrix import (  # noqa: E402
    ALLOWED_SOURCE_LAYERS_BY_OUTPUT,
    allowed_layers_for_output,
)


def test_enrich_allows_clean_not_raw():
    allowed = allowed_layers_for_output("enrich")
    assert allowed is not None
    assert "clean" in allowed
    assert "enrich" in allowed
    assert "transactional" in allowed
    assert "raw" not in allowed


def test_transactional_allowed_for_enrich_and_core_only():
    """datalake_*_transactional maps to layer transactional; enrich and core may read it."""
    for output_layer in (
        "raw",
        "clean",
        "dw",
        "metric",
        "qube",
        "reverse",
    ):
        allowed = allowed_layers_for_output(output_layer)
        assert allowed is not None
        assert "transactional" not in allowed, output_layer
    assert "transactional" in allowed_layers_for_output("enrich")
    assert "transactional" in allowed_layers_for_output("core")


def test_clean_allows_raw():
    allowed = allowed_layers_for_output("clean")
    assert allowed is not None
    assert "raw" in allowed
    assert "clean" in allowed


def test_core_allows_clean_core_transactional():
    allowed = allowed_layers_for_output("core")
    assert allowed is not None
    assert allowed == frozenset({"clean", "core", "transactional"})


def test_unknown_layer_returns_none():
    assert allowed_layers_for_output("not_a_layer") is None
    assert allowed_layers_for_output("") is None


def test_matrix_covers_expected_outputs():
    assert "dw" in ALLOWED_SOURCE_LAYERS_BY_OUTPUT
    assert "metric" in ALLOWED_SOURCE_LAYERS_BY_OUTPUT
    assert "qube" in ALLOWED_SOURCE_LAYERS_BY_OUTPUT
    assert "reverse" in ALLOWED_SOURCE_LAYERS_BY_OUTPUT
