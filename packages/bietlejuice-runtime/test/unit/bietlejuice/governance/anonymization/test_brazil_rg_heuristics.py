import pytest

from bietlejuice.governance.anonymization.brazil_rg_heuristics import (
    apply_brazil_rg_to_cleaned_results,
    apply_brazil_rg_to_nested_cleaned_results,
    can_promote_rg,
    normalize_rg_value,
    should_keep_brazil_rg,
    ssp_sp_check_digit_valid,
)


class TestShouldKeepBrazilRg:
    @pytest.mark.parametrize(
        "column_name,value,expected",
        [
            ("user_phone", "11987654321", False),
            ("cost_amount", "12.345,67", False),
            ("invoice_id", "12345678901", False),
            ("numero_rg", "123456789", True),
            ("documento_rg", "12.345.678-9", True),
            ("customer_rg", "12030001", True),
            ("descricao", "12.345.678-9", False),
            ("rg_telefone", "11987654321", False),
            ("numero_rg", "12.345.678-9", True),
            ("identidade_genero", "123456789", False),
        ],
    )
    def test_column_value_pairs(self, column_name, value, expected):
        # act
        keep = should_keep_brazil_rg(column_name, value)

        # assert
        assert keep is expected


class TestSspSpCheckDigit:
    def test_ghiorzi_example(self):
        # act
        valid = ssp_sp_check_digit_valid(normalize_rg_value("120300011"))

        # assert
        assert valid is True

    def test_with_x_suffix(self):
        # act
        valid = ssp_sp_check_digit_valid(normalize_rg_value("37606335X"))

        # assert
        assert valid is True


class TestApplyBrazilRg:
    def test_filters_false_positive_on_phone_column(self):
        # arrange
        cleaned = [{"type": "BRAZIL_RG", "score": 0.85, "matched_value": "11987654321"}]

        # act
        result = apply_brazil_rg_to_cleaned_results(
            cleaned, "user_phone", ["11987654321"], promote_if_missing=False
        )

        # assert
        assert result[0]["type"] == "NOT_FOUND"

    def test_promotes_on_strong_column(self):
        # arrange
        cleaned = [{"type": "NOT_FOUND", "score": 0.0, "matched_value": "99.999.999-0"}]

        # act
        result = apply_brazil_rg_to_cleaned_results(
            cleaned, "user_rg", ["99.999.999-0"], promote_if_missing=True
        )

        # assert
        assert any(item["type"] == "BRAZIL_RG" for item in result)

    def test_nested_filters_per_sample(self):
        # arrange
        nested = [
            [{"type": "BRAZIL_RG", "score": 0.85, "matched_value": "11987654321"}],
            [{"type": "BRAZIL_RG", "score": 0.85, "matched_value": "2415.0"}],
        ]

        # act
        result = apply_brazil_rg_to_nested_cleaned_results(
            nested, "phone_number", ["11987654321", "2415.0"], promote_if_missing=False
        )

        # assert
        assert result[0][0]["type"] == "NOT_FOUND"
        assert result[1][0]["type"] == "NOT_FOUND"

    def test_nested_promotion_on_every_eligible_sample(self):
        # arrange
        nested = [
            [{"type": "NOT_FOUND", "score": 0.0, "matched_value": "99.999.999-0"}],
            [{"type": "NOT_FOUND", "score": 0.0, "matched_value": "24.678.131-4"}],
        ]

        # act
        result = apply_brazil_rg_to_nested_cleaned_results(
            nested, "user_rg", ["99.999.999-0", "24.678.131-4"], promote_if_missing=True
        )

        # assert
        assert len(result) == 2
        assert all(chunk[0]["type"] == "BRAZIL_RG" for chunk in result)

    def test_nested_promotion_not_blocked_by_other_sample_with_rg(self):
        # arrange
        nested = [
            [{"type": "BRAZIL_RG", "score": 0.85, "matched_value": "99.999.999-0"}],
            [{"type": "NOT_FOUND", "score": 0.0, "matched_value": "24.678.131-4"}],
        ]

        # act
        result = apply_brazil_rg_to_nested_cleaned_results(
            nested, "user_rg", ["99.999.999-0", "24.678.131-4"], promote_if_missing=True
        )

        # assert
        assert result[0][0]["type"] == "BRAZIL_RG"
        assert result[1][0]["type"] == "BRAZIL_RG"


class TestCanPromoteRg:
    @pytest.mark.parametrize(
        "column_name",
        [
            "cdc_transaction_id",
            "id_case",
            "ticket_number",
            "ts_cdc_transaction",
            "ip_address",
        ],
    )
    def test_generic_columns_blocked(self, column_name):
        # act / assert
        assert not can_promote_rg(column_name)
        assert not should_keep_brazil_rg(column_name, "12345678")

    def test_ipv4_value_rejected(self):
        # act
        keep = should_keep_brazil_rg("client_ip", "192.168.1.1")

        # assert
        assert keep is False

    def test_strong_rg_column_keeps_formatted_value(self):
        # act
        keep = should_keep_brazil_rg("rg_id", "24.678.131-4")

        # assert
        assert keep is True

    def test_generic_column_promotion_blocked_in_nested(self):
        # arrange
        nested = [[{"type": "NOT_FOUND", "score": 0.0, "matched_value": "12345678"}]]

        # act
        result = apply_brazil_rg_to_nested_cleaned_results(
            nested, "cdc_transaction_id", ["12345678"], promote_if_missing=True
        )

        # assert
        assert all(item["type"] != "BRAZIL_RG" for chunk in result for item in chunk)

    @pytest.mark.parametrize(
        "value", ["2025-12-15", "15/12/2025", "2025-12-15T10:30:00"]
    )
    def test_date_values_rejected(self, value):
        # act / assert
        assert not should_keep_brazil_rg("contract_annulment", value)
        assert not should_keep_brazil_rg("contract_start", value)

    def test_date_value_promotion_blocked_in_nested(self):
        # arrange
        nested = [[{"type": "NOT_FOUND", "score": 0.0, "matched_value": "2025-12-15"}]]

        # act
        result = apply_brazil_rg_to_nested_cleaned_results(
            nested, "contract_start", ["2025-12-15"], promote_if_missing=True
        )

        # assert
        assert all(item["type"] != "BRAZIL_RG" for chunk in result for item in chunk)

    @pytest.mark.parametrize(
        "column_name",
        ["agent_email", "sale_price", "latitude", "rev", "due_amount"],
    )
    def test_non_document_columns_reject_rg(self, column_name):
        # act / assert
        assert not can_promote_rg(column_name)
        assert not should_keep_brazil_rg(column_name, "12345678")
