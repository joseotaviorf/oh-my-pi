import json
import unittest

from bietlejuice.governance.fairness_assessment import (
    assess_column_description_quality,
    assess_table_description_quality,
    compute_f2_02_and_i1_01_for_fqn,
)
from bietlejuice.governance.fairness_assessment.checks.findable.f2_02_substantive_column_descriptions import (  # noqa: E501
    check_f2_02_substantive_column_descriptions,
)
from bietlejuice.governance.fairness_assessment.checks.interoperable.i1_01_documented_physical_fields import (  # noqa: E501
    check_i1_01_documented_physical_fields,
)


class TestAssessTableDescriptionQuality(unittest.TestCase):
    def test_empty_description(self):
        r = assess_table_description_quality("s", "t", None)
        self.assertFalse(r.is_substantive)
        self.assertEqual(r.reason_code, "empty")

    def test_motivator_pt_boilerplate_echo(self):
        r = assess_table_description_quality(
            "datalake_x_clean",
            "usuarios",
            "tabela com informacoes de usuarios",
        )
        self.assertFalse(r.is_substantive)
        self.assertEqual(r.reason_code, "boilerplate_or_name_echo")

    def test_motivator_accented_usuarios(self):
        r = assess_table_description_quality(
            "core",
            "usuarios",
            "Tabela com informações de usuários",
        )
        self.assertFalse(r.is_substantive)
        self.assertIn(
            r.reason_code,
            ("boilerplate_or_name_echo", "too_short"),
        )

    def test_substantive_long_pt(self):
        r = assess_table_description_quality(
            "dw_rent",
            "fact_contract",
            "Contratos de aluguel firmados com valores, datas de assinatura e vínculo ao imóvel; "
            "usado pelo time de Rent para métricas de receita.",
        )
        self.assertTrue(r.is_substantive)
        self.assertIsNone(r.reason_code)
        self.assertGreaterEqual(r.non_identifier_word_count, 2)

    def test_only_snake_case_words_from_name(self):
        r = assess_table_description_quality(
            "dw_rent",
            "fact_contract",
            "fact contract dw rent",
        )
        self.assertFalse(r.is_substantive)

    def test_repeated_fqn_like_string(self):
        r = assess_table_description_quality(
            "dw_rent",
            "fact_contract",
            "dw_rent fact_contract",
        )
        self.assertFalse(r.is_substantive)

    def test_two_extra_words_passes(self):
        r = assess_table_description_quality(
            "s",
            "orders",
            "Pedidos ecommerce com status e valor total por linha",
        )
        self.assertTrue(r.is_substantive)

    def test_column_substantive_beyond_name(self):
        r = assess_column_description_quality(
            "dw",
            "t",
            "amount_paid",
            "Valor bruto pago na transação, incluindo impostos e comissão da plataforma",
        )
        self.assertTrue(r.is_substantive)
        self.assertIsNone(r.reason_code)

    def test_column_echo_name_only_fails(self):
        r = assess_column_description_quality("dw", "t", "amount_paid", "amount paid")
        self.assertFalse(r.is_substantive)


class TestF2I1ColumnInteroperability(unittest.TestCase):
    def test_f2_fails_missing_docs_when_physical(self):
        f2, i1, detail_json, cols_sub = compute_f2_02_and_i1_01_for_fqn(
            "a",
            "b",
            {},
            spark_table_exists=True,
            physical_field_names_lower=frozenset({"x", "y"}),
        )
        self.assertFalse(cols_sub)
        self.assertFalse(f2.passed)
        self.assertEqual(f2.reason, "no_column_docs_in_lake")
        self.assertFalse(i1.passed)
        d = json.loads(detail_json)
        self.assertEqual(d["undocumented_business_names"], ["x", "y"])
        self.assertEqual(d["undocumented_partition_names"], [])

    def test_i1_passes_when_no_catalog_table(self):
        long_desc = "This column stores the user identifier for cross-referencing with other dimensions."
        f2, i1, detail_json, cols_sub = compute_f2_02_and_i1_01_for_fqn(
            "a",
            "b",
            {"c": long_desc},
            spark_table_exists=False,
            physical_field_names_lower=frozenset(),
        )
        self.assertTrue(cols_sub)
        self.assertTrue(i1.passed)
        self.assertTrue(f2.passed)
        d = json.loads(detail_json)
        self.assertEqual(d["undocumented_business_names"], [])
        self.assertEqual(d["undocumented_partition_names"], [])

    def test_i1_passes_with_warning_when_only_partition_columns_undocumented(self):
        long = "Identifier column used in joins; stable surrogate key for the business entity in this table."
        f2, i1, detail_json, cols_sub = compute_f2_02_and_i1_01_for_fqn(
            "a",
            "b",
            {"id": long},
            spark_table_exists=True,
            physical_field_names_lower=frozenset({"id", "year", "month"}),
        )
        self.assertTrue(cols_sub)
        self.assertTrue(i1.passed)
        d = json.loads(detail_json)
        self.assertEqual(d["undocumented_business_names"], [])
        self.assertEqual(d["undocumented_partition_names"], ["month", "year"])
        self.assertIn("warnings", d)
        self.assertIn("undocumented_partition_columns", d["warnings"][0])

    def test_i1_fails_when_business_and_partition_missing(self):
        long = "Identifier column used in joins; stable surrogate key for the business entity in this table."
        f2, i1, detail_json, cols_sub = compute_f2_02_and_i1_01_for_fqn(
            "a",
            "b",
            {"id": long},
            spark_table_exists=True,
            physical_field_names_lower=frozenset({"id", "day", "extra_col", "year"}),
        )
        self.assertTrue(cols_sub)
        self.assertFalse(i1.passed)
        self.assertEqual(i1.reason, "undocumented_columns")
        d = json.loads(detail_json)
        self.assertEqual(d["undocumented_business_names"], ["extra_col"])
        self.assertEqual(set(d["undocumented_partition_names"]), {"day", "year"})
        self.assertNotIn("warnings", d)

    def test_columns_sub_false_when_no_column_docs_in_batch(self):
        f2, i1, _detail, cols_sub = compute_f2_02_and_i1_01_for_fqn(
            "a",
            "b",
            {},
            spark_table_exists=False,
            physical_field_names_lower=frozenset(),
        )
        self.assertFalse(cols_sub)
        self.assertTrue(f2.passed)
        self.assertTrue(i1.passed)

    def test_columns_sub_false_when_one_column_not_substantive(self):
        long = "Identifier column used in joins; stable surrogate key for the business entity in this table."
        f2, i1, _detail, cols_sub = compute_f2_02_and_i1_01_for_fqn(
            "a",
            "b",
            {
                "id": long,
                "bad": "id",
            },
            spark_table_exists=True,
            physical_field_names_lower=frozenset({"id", "bad"}),
        )
        self.assertFalse(cols_sub)
        self.assertFalse(f2.passed)


class TestRowBackedF2I1Checks(unittest.TestCase):
    def test_f2_02_not_assessed_when_pass_missing(self):
        r = check_f2_02_substantive_column_descriptions(None, None)
        self.assertEqual(r.requirement_id, "F2-02")
        self.assertFalse(r.passed)
        self.assertEqual(r.reason, "f2_02_not_assessed")

    def test_f2_02_pass_from_row_fields(self):
        r = check_f2_02_substantive_column_descriptions(True, None)
        self.assertTrue(r.passed)
        self.assertIsNone(r.reason)

    def test_i1_01_fail_reason_normalized(self):
        r = check_i1_01_documented_physical_fields(False, "  undocumented_columns  ")
        self.assertFalse(r.passed)
        self.assertEqual(r.reason, "undocumented_columns")

    def test_i1_01_not_assessed(self):
        r = check_i1_01_documented_physical_fields(None, None)
        self.assertFalse(r.passed)
        self.assertEqual(r.reason, "i1_01_not_assessed")


if __name__ == "__main__":
    unittest.main()
