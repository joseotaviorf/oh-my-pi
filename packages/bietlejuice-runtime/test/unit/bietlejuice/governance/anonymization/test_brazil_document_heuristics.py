from bietlejuice.governance.anonymization.brazil_document_heuristics import (
    apply_brazil_document_to_cleaned_results,
    apply_brazil_document_to_nested_cleaned_results,
    is_document_like_column,
    is_valid_cnpj,
    is_valid_cpf,
    should_keep_brazil_cnpj,
    should_keep_brazil_cpf,
)


class TestCpfCnpjValidation:
    def test_valid_cpf_known_good(self):
        # act
        valid = is_valid_cpf("39053344705")

        # assert
        assert valid is True

    def test_invalid_cpf_rejects_invoice_like_sequence(self):
        # act
        valid = is_valid_cpf("12345678901")

        # assert
        assert valid is False

    def test_valid_cnpj_known_good(self):
        # act
        valid = is_valid_cnpj("04252011000110")

        # assert
        assert valid is True


class TestShouldKeepBrazilDocuments:
    def test_rejects_invalid_cpf_on_invoice_column(self):
        # act
        keep = should_keep_brazil_cpf("id_invoice", "12345678901")

        # assert
        assert keep is False

    def test_keeps_formatted_cpf(self):
        # act
        keep = should_keep_brazil_cpf("user_cpf", "390.533.447-05")

        # assert
        assert keep is True

    def test_keeps_formatted_cnpj(self):
        # act
        keep = should_keep_brazil_cnpj("company_cnpj", "04.252.011/0001-10")

        # assert
        assert keep is True


class TestDocumentLikeColumns:
    def test_national_document_number(self):
        # act
        document_like = is_document_like_column("national_document_number")

        # assert
        assert document_like is True


class TestApplyBrazilDocument:
    def test_demotes_invalid_cpf_hit(self):
        # arrange
        cleaned = [
            {"type": "BRAZIL_CPF", "score": 0.85, "matched_value": "12345678901"}
        ]

        # act
        result = apply_brazil_document_to_cleaned_results(
            cleaned, "contract_id", ["12345678901"], promote_if_missing=False
        )

        # assert
        assert result[0]["type"] == "NOT_FOUND"

    def test_nested_promotion_preserves_sample_alignment(self):
        # arrange
        nested = [
            [{"type": "NOT_FOUND", "score": 0.0, "matched_value": "39053344705"}],
            [{"type": "NOT_FOUND", "score": 0.0, "matched_value": "not-a-document"}],
        ]

        # act
        result = apply_brazil_document_to_nested_cleaned_results(
            nested, "national_document_number", ["39053344705", "not-a-document"]
        )

        # assert
        assert len(result) == 2
        assert any(item["type"] == "BRAZIL_CPF" for item in result[0])
        assert all(item["type"] != "BRAZIL_CPF" for item in result[1])
