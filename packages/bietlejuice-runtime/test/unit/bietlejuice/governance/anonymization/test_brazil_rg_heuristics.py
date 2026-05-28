"""Mirrors tests/dags/governance/enrich_anonymization/test_brazil_rg_heuristics.py."""

from bietlejuice.governance.anonymization.brazil_rg_heuristics import (
    apply_brazil_rg_to_nested_cleaned_results,
    should_keep_brazil_rg,
)


def test_nested_phone_values_do_not_keep_rg():
    nested = [
        [{"type": "BRAZIL_RG", "score": 0.85, "matched_value": "+5561986224065"}],
    ]
    result = apply_brazil_rg_to_nested_cleaned_results(
        nested, "phone_number", ["+5561986224065"], promote_if_missing=False
    )
    assert result[0][0]["type"] == "NOT_FOUND"


def test_should_keep_rg_on_rg_column():
    assert should_keep_brazil_rg("user_rg", "99.999.999-0")
