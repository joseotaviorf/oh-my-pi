import pytest

from bietlejuice.governance.anonymization.brazil_rg_heuristics import (
    apply_brazil_rg_to_cleaned_results,
    apply_brazil_rg_to_nested_cleaned_results,
    normalize_rg_value,
    should_keep_brazil_rg,
    ssp_sp_check_digit_valid,
)


@pytest.mark.parametrize(
    "column_name,value,expected",
    [
        ("user_phone", "11987654321", False),
        ("cost_amount", "12.345,67", False),
        ("invoice_id", "12345678901", False),
        ("numero_rg", "123456789", True),
        ("documento_rg", "12.345.678-9", True),
        ("customer_rg", "12030001", True),
        ("descricao", "12.345.678-9", True),
        ("rg_telefone", "11987654321", False),
        ("numero_rg", "12.345.678-9", True),
        ("identidade_genero", "123456789", False),
    ],
)
def test_should_keep_brazil_rg(column_name, value, expected):
    assert should_keep_brazil_rg(column_name, value) is expected


def test_ssp_sp_check_digit_ghiorzi_example():
    # Ghiorzi SSP-SP: body 12030001 + check digit 1 (9 chars total).
    assert ssp_sp_check_digit_valid(normalize_rg_value("120300011"))


def test_ssp_sp_check_digit_with_x():
    assert ssp_sp_check_digit_valid(normalize_rg_value("37606335X"))


def test_apply_brazil_rg_filters_false_positive():
    cleaned = [
        {"type": "BRAZIL_RG", "score": 0.85, "matched_value": "11987654321"},
    ]
    result = apply_brazil_rg_to_cleaned_results(
        cleaned, "user_phone", ["11987654321"], promote_if_missing=False
    )
    assert result[0]["type"] == "NOT_FOUND"


def test_apply_brazil_rg_promotes_on_strong_column():
    cleaned = [{"type": "NOT_FOUND", "score": 0.0, "matched_value": "99.999.999-0"}]
    result = apply_brazil_rg_to_cleaned_results(
        cleaned, "user_rg", ["99.999.999-0"], promote_if_missing=True
    )
    assert any(item["type"] == "BRAZIL_RG" for item in result)


def test_apply_brazil_rg_nested_per_sample_value():
    nested = [
        [{"type": "BRAZIL_RG", "score": 0.85, "matched_value": "11987654321"}],
        [{"type": "BRAZIL_RG", "score": 0.85, "matched_value": "2415.0"}],
    ]
    result = apply_brazil_rg_to_nested_cleaned_results(
        nested, "phone_number", ["11987654321", "2415.0"], promote_if_missing=False
    )
    assert result[0][0]["type"] == "NOT_FOUND"
    assert result[1][0]["type"] == "NOT_FOUND"
