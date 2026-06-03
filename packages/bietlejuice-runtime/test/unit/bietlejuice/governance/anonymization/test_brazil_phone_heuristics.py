import pytest

from bietlejuice.governance.anonymization.brazil_phone_heuristics import (
    PHONE_NUMBER_ENTITY,
    apply_phone_to_cleaned_results,
    apply_phone_to_nested_cleaned_results,
    looks_like_brazil_phone,
    should_keep_phone,
)


class TestLooksLikeBrazilPhone:
    @pytest.mark.parametrize(
        "value",
        [
            "11987654321",
            "(11) 98765-4321",
            "+55 11 98765-4321",
            "5511987654321",
            "1133224455",
            "(11) 3322-4455",
        ],
    )
    def test_positive_shapes(self, value):
        # act
        result = looks_like_brazil_phone(value)

        # assert
        assert result is True

    @pytest.mark.parametrize(
        "value",
        ["12345", "00000000000", "0987654321", "11887654321", "1.234.567,89", "", None],
    )
    def test_negative_shapes(self, value):
        # act
        result = looks_like_brazil_phone(value)

        # assert
        assert result is False

    def test_valid_cpf_not_treated_as_phone(self):
        # act
        result = looks_like_brazil_phone("39053344705")

        # assert
        assert result is False


class TestShouldKeepPhone:
    def test_keeps_valid_mobile(self):
        # act
        assert should_keep_phone("mobile_phone", "11987654321") is True
        assert should_keep_phone("mobile_phone", "not-a-phone") is False


class TestApplyPhoneHeuristics:
    def test_promotes_on_phone_column_per_sample(self):
        # arrange
        nested = [
            [{"type": "NOT_FOUND", "score": 0.0, "matched_value": "11987654321"}],
            [{"type": "NOT_FOUND", "score": 0.0, "matched_value": "(21) 99876-5432"}],
        ]

        # act
        result = apply_phone_to_nested_cleaned_results(
            nested,
            "consorcio_phone_number_formatted",
            ["11987654321", "(21) 99876-5432"],
        )

        # assert
        assert len(result) == 2
        assert all(len(chunk) == 1 for chunk in result)
        promoted = [item["type"] for chunk in result for item in chunk]
        assert promoted.count(PHONE_NUMBER_ENTITY) == 2

    def test_promotion_replaces_not_found_without_duplicate(self):
        # arrange
        cleaned = [{"type": "NOT_FOUND", "score": 0.0, "matched_value": "11987654321"}]

        # act
        result = apply_phone_to_cleaned_results(
            cleaned, "mobile_phone", ["11987654321"], promote_if_missing=True
        )

        # assert
        assert len(result) == 1
        assert result[0]["type"] == PHONE_NUMBER_ENTITY

    def test_promotion_after_invalid_hit_demoted_in_place(self):
        # arrange
        cleaned = [
            {
                "type": PHONE_NUMBER_ENTITY,
                "score": 0.85,
                "matched_value": "not-a-phone",
            },
        ]

        # act
        result = apply_phone_to_cleaned_results(
            cleaned, "mobile_phone", ["11987654321"], promote_if_missing=True
        )

        # assert
        assert len(result) == 1
        assert result[0]["type"] == PHONE_NUMBER_ENTITY
        assert result[0]["matched_value"] == "11987654321"

    def test_keeps_valid_presidio_hit(self):
        # arrange
        nested = [
            [
                {
                    "type": PHONE_NUMBER_ENTITY,
                    "score": 0.85,
                    "matched_value": "11987654321",
                }
            ]
        ]

        # act
        result = apply_phone_to_nested_cleaned_results(
            nested, "mobile_phone", ["11987654321"]
        )

        # assert
        assert result[0][0]["type"] == PHONE_NUMBER_ENTITY

    def test_demotes_garbage_value(self):
        # arrange
        nested = [[{"type": PHONE_NUMBER_ENTITY, "score": 0.85, "matched_value": "12"}]]

        # act
        result = apply_phone_to_nested_cleaned_results(nested, "ddd_phone", ["12"])

        # assert
        assert result[0][0]["type"] == "NOT_FOUND"

    def test_no_promotion_on_non_phone_column(self):
        # arrange
        nested = [[{"type": "NOT_FOUND", "score": 0.0, "matched_value": "11987654321"}]]

        # act
        result = apply_phone_to_nested_cleaned_results(
            nested, "id_application", ["11987654321"]
        )

        # assert
        promoted = [item["type"] for chunk in result for item in chunk]
        assert PHONE_NUMBER_ENTITY not in promoted
