"""Tests for DATE_TIME validation heuristics (production loader path)."""

import pytest

from bietlejuice.governance.anonymization.brazil_datetime_heuristics import (
    apply_datetime_demotion_when_document_present,
    apply_datetime_heuristics_to_cleaned_results,
    column_demotes_date_time,
    should_keep_date_time,
)
from bietlejuice.governance.anonymization.brazil_document_heuristics import (
    apply_brazil_document_to_cleaned_results,
    is_document_like_column,
)
from bietlejuice.governance.anonymization.brazil_rg_heuristics import (
    apply_brazil_rg_to_cleaned_results,
    should_keep_brazil_rg,
)


def _wave1_chunk(chunk, column_name, raw_value):
    cleaned = apply_brazil_document_to_cleaned_results(
        chunk, column_name, [raw_value], promote_if_missing=True
    )
    cleaned = apply_brazil_rg_to_cleaned_results(
        cleaned, column_name, [raw_value], promote_if_missing=True
    )
    return apply_datetime_heuristics_to_cleaned_results(cleaned, column_name)


class TestColumnDemotesDateTime:
    @pytest.mark.parametrize(
        "column_name",
        [
            "id_candidate",
            "id_application",
            "associations",
            "mobile_phone",
            "national_document_number",
        ],
    )
    def test_demoted_columns_reject_date_time(self, column_name):
        # act
        demotes = column_demotes_date_time(column_name)
        keep = should_keep_date_time(column_name, "47652588820", 0.85)

        # assert
        assert demotes is True
        assert keep is False

    def test_money_column_rejects_via_value_shape(self):
        # act
        demotes = column_demotes_date_time("plr_monthly_brl")
        keep = should_keep_date_time("plr_monthly_brl", "47652588820", 0.85)

        # assert
        assert demotes is False
        assert keep is False


class TestShouldKeepDateTime:
    def test_temporal_column_accepts_iso_and_compact(self):
        # act / assert
        assert should_keep_date_time("dt_created", "2024-03-15", 0.85) is True
        assert should_keep_date_time("created_at", "2024-03-15", 0.85) is True
        assert should_keep_date_time("ts_created", "20240315", 0.85) is True

    def test_epoch_column_accepts_unix_seconds(self):
        # act
        keep = should_keep_date_time("epoch_event", "1717334400", 0.85)

        # assert
        assert keep is True

    @pytest.mark.parametrize(
        "column_name,value",
        [
            ("dt_created", "20240315"),
            ("dt_signed", "20240602"),
            ("ts_updated", "240315"),
            ("created_at", "2024031"),
        ],
    )
    def test_compact_numeric_on_temporal_columns(self, column_name, value):
        # act
        keep = should_keep_date_time(column_name, value, 0.85)

        # assert
        assert keep is True

    def test_id_column_rejects_compact_numeric(self):
        # act
        keep = should_keep_date_time("id_candidate", "20240315", 0.85)

        # assert
        assert keep is False

    def test_explicit_date_on_neutral_column(self):
        # act / assert
        assert should_keep_date_time("description", "2024-03-15", 0.85) is True
        assert should_keep_date_time("product_code", "15/12/2025", 0.85) is True

    def test_identifier_column_demotes_with_date_shaped_value(self):
        # act
        keep = should_keep_date_time("id_created_by", "2024-03-15", 0.85)

        # assert
        assert keep is False


class TestApplyDatetimeHeuristics:
    def test_demoted_when_cpf_kept_on_same_value(self):
        # arrange
        chunk = [
            {"type": "DATE_TIME", "score": 0.85, "matched_value": "400.453.018-08"},
            {"type": "BRAZIL_CPF", "score": 0.85, "matched_value": "400.453.018-08"},
        ]

        # act
        result = apply_datetime_demotion_when_document_present(
            chunk, "national_document_number"
        )

        # assert
        assert [item["type"] for item in result] == ["NOT_FOUND", "BRAZIL_CPF"]

    def test_not_demoted_on_temporal_column_with_cpf(self):
        # arrange
        chunk = [
            {"type": "DATE_TIME", "score": 0.85, "matched_value": "2024-03-15"},
            {"type": "BRAZIL_CPF", "score": 0.85, "matched_value": "2024-03-15"},
        ]

        # act
        result = apply_datetime_demotion_when_document_present(chunk, "dt_created")

        # assert
        assert result[0]["type"] == "DATE_TIME"

    def test_not_demoted_for_untrusted_rg_on_generic_column(self):
        # arrange
        chunk = [
            {"type": "DATE_TIME", "score": 0.85, "matched_value": "12345678"},
            {"type": "BRAZIL_RG", "score": 0.85, "matched_value": "12345678"},
        ]

        # act
        result = apply_datetime_demotion_when_document_present(chunk, "ticket_number")

        # assert
        assert result[0]["type"] == "DATE_TIME"

    @pytest.mark.parametrize(
        "column_name",
        ["id_created_by", "id_last_modified_by", "created_by", "application_id"],
    )
    def test_identifier_columns_demote_via_filter(self, column_name):
        # arrange
        value = "005bL00000JNWCLQA5"

        # act
        result = apply_datetime_heuristics_to_cleaned_results(
            [{"type": "DATE_TIME", "score": 0.85, "matched_value": value}],
            column_name,
        )

        # assert
        assert result[0]["type"] == "NOT_FOUND"

    def test_filter_demotes_id_candidate_numeric_value(self):
        # arrange
        chunk = [{"type": "DATE_TIME", "score": 0.85, "matched_value": "12345678901"}]

        # act
        result = apply_datetime_heuristics_to_cleaned_results(chunk, "id_candidate")

        # assert
        assert result[0]["type"] == "NOT_FOUND"


class TestDocumentLikeColumnHelpers:
    def test_national_document_number_is_document_like(self):
        # act
        document_like = is_document_like_column("national_document_number")

        # assert
        assert document_like is True

    @pytest.mark.parametrize(
        "column_name",
        ["id_candidate", "mobile_phone", "deal.associations"],
    )
    def test_non_document_columns(self, column_name):
        # act
        document_like = is_document_like_column(column_name)

        # assert
        assert document_like is False

    def test_rg_kept_on_national_document_eleven_digits(self):
        # act
        keep = should_keep_brazil_rg("national_document_number", "20459817787")

        # assert
        assert keep is True


class TestWave1DatetimeIntegration:
    def test_invalid_cpf_on_document_column_demotes_datetime_keeps_rg(self):
        # arrange
        chunk = [
            {"type": "DATE_TIME", "score": 0.85, "matched_value": "20459817787"},
            {"type": "BRAZIL_RG", "score": 0.85, "matched_value": "20459817787"},
            {"type": "BRAZIL_CPF", "score": 0.85, "matched_value": "20459817787"},
        ]

        # act
        cleaned = _wave1_chunk(chunk, "national_document_number", "20459817787")
        types = [item["type"] for item in cleaned]

        # assert
        assert "BRAZIL_RG" in types
        assert "DATE_TIME" not in types

    def test_national_document_samples_demote_datetime_on_cpf_values(self):
        # arrange
        presidio_rows = [
            [
                {"type": "BRAZIL_RG", "score": 0.85, "matched_value": "47137155812"},
                {"type": "BRAZIL_CPF", "score": 0.85, "matched_value": "47137155812"},
            ],
            [
                {"type": "DATE_TIME", "score": 0.85, "matched_value": "20459817787"},
                {"type": "BRAZIL_RG", "score": 0.85, "matched_value": "20459817787"},
                {"type": "BRAZIL_CPF", "score": 0.85, "matched_value": "20459817787"},
            ],
            [
                {"type": "DATE_TIME", "score": 0.85, "matched_value": "400.453.018-08"},
                {
                    "type": "BRAZIL_CPF",
                    "score": 0.85,
                    "matched_value": "400.453.018-08",
                },
            ],
        ]
        column = "national_document_number"

        # act
        nested = [
            _wave1_chunk(group, column, group[0]["matched_value"])
            for group in presidio_rows
        ]

        # assert
        assert (
            sum(1 for chunk in nested for item in chunk if item["type"] == "BRAZIL_CPF")
            >= 2
        )
        assert all(
            item["type"] != "DATE_TIME"
            for chunk in nested
            for item in chunk
            if item["matched_value"] in ("400.453.018-08", "20459817787")
        )
