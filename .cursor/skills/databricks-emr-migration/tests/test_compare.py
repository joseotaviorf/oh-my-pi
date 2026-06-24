import sys
import unittest
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL_DIR))

from compare import (
    compare_count,
    compare_results,
    compare_sample,
    compare_schema,
    schema_for_compare,
)
from models import EmrTableResult, TableBaseline


class CompareTests(unittest.TestCase):
    def test_schema_exact_match(self) -> None:
        ok, issues, warn = compare_schema(
            [("sk_offer", "bigint"), ("sk_client", "bigint")],
            [("sk_offer", "bigint"), ("sk_client", "bigint")],
        )
        self.assertTrue(ok)
        self.assertFalse(warn)
        self.assertEqual(issues, [])

    def test_schema_widening_warn(self) -> None:
        ok, issues, warn = compare_schema(
            [("sk_offer", "int")],
            [("sk_offer", "bigint")],
        )
        self.assertTrue(ok)
        self.assertTrue(warn)

    def test_schema_column_order_mismatch_records_issue(self) -> None:
        ok, issues, warn = compare_schema(
            [("sk_offer", "bigint"), ("sk_client", "bigint")],
            [("sk_client", "bigint"), ("sk_offer", "bigint")],
        )
        self.assertFalse(ok)
        self.assertFalse(warn)
        self.assertEqual(len(issues), 1)
        self.assertIn("Column order mismatch", issues[0])

    def test_compare_results_schema_order_mismatch_surfaces_issue(self) -> None:
        baseline = TableBaseline(
            dag="dw_credit_analysis",
            table="fact_offer_early_credit",
            layer="dw",
            load_start_date="2026-06-04",
            schema=[("sk_offer", "bigint"), ("sk_client", "bigint")],
            count=10,
            sample_rows=1,
            sample=[{"sk_offer": 1, "sk_client": 2}],
            order_by_cols=["sk_offer"],
            time_pinned_functions=[],
            non_comparable_cols=["ts_load"],
        )
        result = compare_results(
            baseline,
            EmrTableResult(
                schema=[("sk_client", "bigint"), ("sk_offer", "bigint")],
                count=10,
                sample=[{"sk_client": 2, "sk_offer": 1}],
            ),
        )
        self.assertEqual(result.status, "FAIL")
        self.assertFalse(result.schema_match)
        self.assertEqual(len(result.schema_issues), 1)
        self.assertIn("Column order mismatch", result.schema_issues[0])

    def test_count_thresholds(self) -> None:
        delta, status = compare_count(1000, 1000)
        self.assertEqual(status, "PASS")
        self.assertEqual(delta, 0.0)

        delta, status = compare_count(1000, 1003)
        self.assertEqual(status, "WARN")

        delta, status = compare_count(1000, 1060)
        self.assertEqual(status, "FAIL")

    def test_sample_timestamp_two_digit_fraction(self) -> None:
        ok, diffs, warn = compare_sample(
            [{"ts_created": "2020-02-21T21:07:12.72Z"}],
            [{"ts_created": "2020-02-21T21:07:12.720000"}],
        )
        self.assertTrue(ok)
        self.assertEqual(diffs, [])

    def test_sample_timestamp_format_equivalent(self) -> None:
        ok, diffs, warn = compare_sample(
            [{"ts_credit_analysis_created": "2020-02-21T21:01:04.605Z"}],
            [{"ts_credit_analysis_created": "2020-02-21T21:01:04.605000"}],
        )
        self.assertTrue(ok)
        self.assertFalse(warn)
        self.assertEqual(diffs, [])

    def test_compare_results_pass_on_timestamp_format_only(self) -> None:
        baseline = TableBaseline(
            dag="dw_credit_analysis",
            table="dim_credit_analysis",
            layer="dw",
            load_start_date="2026-06-04",
            schema=[("ts_credit_analysis_created", "timestamp")],
            count=5_958_520,
            sample_rows=1,
            sample=[{"ts_credit_analysis_created": "2020-02-21T21:01:04.605Z"}],
            order_by_cols=["ts_credit_analysis_created"],
            time_pinned_functions=[],
            non_comparable_cols=["ts_load"],
        )
        result = compare_results(
            baseline,
            EmrTableResult(
                schema=[("ts_credit_analysis_created", "timestamp")],
                count=5_958_520,
                sample=[{"ts_credit_analysis_created": "2020-02-21T21:01:04.605000"}],
            ),
        )
        self.assertEqual(result.status, "PASS")
        self.assertTrue(result.sample_match)

    def test_count_tiny_absolute_delta_still_passes(self) -> None:
        delta, status = compare_count(5_909_897, 5_909_893)
        self.assertEqual(status, "PASS")
        self.assertLess(delta, 0.1)

    def test_sample_ignores_ts_load(self) -> None:
        ok, diffs, _ = compare_sample(
            [{"sk_offer": 1, "ts_load": "a"}],
            [{"sk_offer": 1, "ts_load": "b"}],
            ["ts_load"],
        )
        self.assertTrue(ok)
        self.assertEqual(diffs, [])

    def test_sample_string_mismatch_is_fail_not_warn(self) -> None:
        ok, diffs, warn = compare_sample(
            [{"dt_signed": "2026-06-04"}],
            [{"dt_signed": "2026-06-05"}],
        )
        self.assertFalse(ok)
        self.assertFalse(warn)
        self.assertEqual(len(diffs), 1)

    def test_sample_int_id_mismatch_is_fail_not_warn(self) -> None:
        ok, diffs, warn = compare_sample(
            [{"sk_offer": 1}],
            [{"sk_offer": 2}],
        )
        self.assertFalse(ok)
        self.assertFalse(warn)
        self.assertEqual(len(diffs), 1)

    def test_sample_length_mismatch_is_fail_not_warn(self) -> None:
        ok, diffs, warn = compare_sample(
            [{"sk_offer": 1}, {"sk_offer": 2}],
            [{"sk_offer": 1}],
        )
        self.assertFalse(ok)
        self.assertFalse(warn)
        self.assertEqual(diffs[0]["issue"], "sample_length_mismatch")

    def test_sample_minor_float_diff_is_warn(self) -> None:
        ok, diffs, warn = compare_sample(
            [{"amount": 1.0}],
            [{"amount": 1.00001}],
        )
        self.assertFalse(ok)
        self.assertTrue(warn)
        self.assertEqual(len(diffs), 1)

    def test_compare_results_fail_on_sample_string_mismatch(self) -> None:
        baseline = TableBaseline(
            dag="dw_credit_analysis",
            table="fact_offer_early_credit",
            layer="dw",
            load_start_date="2026-06-04",
            schema=[("sk_offer", "bigint"), ("dt_signed", "date")],
            count=1,
            sample_rows=1,
            sample=[{"sk_offer": 1, "dt_signed": "2026-06-04"}],
            order_by_cols=["sk_offer"],
            time_pinned_functions=[],
            non_comparable_cols=[],
        )
        result = compare_results(
            baseline,
            EmrTableResult(
                schema=[("sk_offer", "bigint"), ("dt_signed", "date")],
                count=1,
                sample=[{"sk_offer": 1, "dt_signed": "2026-06-05"}],
            ),
            skip_sample=False,
        )
        self.assertEqual(result.status, "FAIL")
        self.assertFalse(result.sample_match)

    def test_compare_results_warn_on_minor_float_diff_labels_sample_warn(self) -> None:
        baseline = TableBaseline(
            dag="dw_credit_analysis",
            table="fact_offer_early_credit",
            layer="dw",
            load_start_date="2026-06-04",
            schema=[("amount", "double")],
            count=1,
            sample_rows=1,
            sample=[{"amount": 1.0}],
            order_by_cols=["amount"],
            time_pinned_functions=[],
            non_comparable_cols=[],
        )
        result = compare_results(
            baseline,
            EmrTableResult(
                schema=[("amount", "double")],
                count=1,
                sample=[{"amount": 1.00001}],
            ),
            skip_sample=False,
        )
        self.assertEqual(result.status, "WARN")
        self.assertFalse(result.sample_match)
        self.assertTrue(result.sample_warn)
        self.assertIn("sample=warn", result.message)

    def test_compare_results_pass_when_both_empty(self) -> None:
        baseline = TableBaseline(
            dag="dw_credit_analysis",
            table="fact_fintechops_tasks",
            layer="dw",
            load_start_date="2026-06-07",
            schema=[],
            count=0,
            sample_rows=0,
            sample=[],
            order_by_cols=[],
            time_pinned_functions=[],
            non_comparable_cols=[],
        )
        result = compare_results(
            baseline,
            EmrTableResult(schema=[], count=0, sample=[]),
        )
        self.assertEqual(result.status, "PASS")
        self.assertTrue(result.schema_match)
        self.assertTrue(result.sample_match)
        self.assertIn("empty table", result.message)

    def test_compare_results_fail_on_emr_error(self) -> None:
        baseline = TableBaseline(
            dag="dw_credit_analysis",
            table="fact_offer_early_credit",
            layer="dw",
            load_start_date="2026-06-04",
            schema=[("sk_offer", "bigint")],
            count=10,
            sample_rows=1,
            sample=[{"sk_offer": 1}],
            order_by_cols=["sk_offer"],
            time_pinned_functions=[],
            non_comparable_cols=["ts_load"],
        )
        result = compare_results(
            baseline,
            EmrTableResult(schema=[], count=0, sample=[], error="boom"),
        )
        self.assertEqual(result.status, "FAIL")

    def test_compare_results_uses_layer_table_label(self) -> None:
        baseline = TableBaseline(
            dag="dw_credit_analysis",
            table="fact_offer_early_credit",
            layer="dw",
            load_start_date="2026-06-04",
            schema=[("sk_offer", "bigint")],
            count=1,
            sample_rows=1,
            sample=[{"sk_offer": 1}],
            order_by_cols=["sk_offer"],
            time_pinned_functions=[],
            non_comparable_cols=[],
        )
        result = compare_results(
            baseline,
            EmrTableResult(
                schema=[("sk_offer", "bigint")],
                count=1,
                sample=[{"sk_offer": 1}],
            ),
        )
        self.assertEqual(result.table, "dw/fact_offer_early_credit")
        self.assertEqual(result.status, "PASS")

    def test_sample_matches_equivalent_rows_in_different_order(self) -> None:
        ok, diffs, warn = compare_sample(
            [
                {"sk_offer": 1, "tier": "a"},
                {"sk_offer": 1, "tier": "b"},
            ],
            [
                {"sk_offer": 1, "tier": "b"},
                {"sk_offer": 1, "tier": "a"},
            ],
        )
        self.assertTrue(ok)
        self.assertFalse(warn)
        self.assertEqual(diffs, [])

    def test_schema_for_compare_strips_excluded_from_both_sides(self) -> None:
        excluded = {"op_cdc", "ts_cdc_transaction", "ts_database_transaction"}
        baseline = schema_for_compare(
            [("id", "bigint"), ("op_cdc", "string")],
            excluded,
        )
        emr = schema_for_compare(
            [("id", "bigint"), ("op_cdc", "string"), ("ts_cdc_transaction", "timestamp")],
            excluded,
        )
        self.assertEqual(baseline, [("id", "bigint")])
        self.assertEqual(emr, [("id", "bigint")])

    def test_compare_results_pass_when_emr_has_extra_cdc_columns(self) -> None:
        baseline = TableBaseline(
            dag="kodak",
            table="watermark_removal",
            layer="clean",
            load_start_date="2026-06-23",
            schema=[("id", "bigint"), ("id_image_inspection", "bigint")],
            count=100,
            sample_rows=0,
            sample=[],
            order_by_cols=["id"],
            time_pinned_functions=[],
            non_comparable_cols=[
                "op_cdc",
                "ts_cdc_transaction",
                "ts_database_transaction",
            ],
        )
        result = compare_results(
            baseline,
            EmrTableResult(
                schema=[
                    ("id", "bigint"),
                    ("id_image_inspection", "bigint"),
                    ("op_cdc", "string"),
                    ("ts_cdc_transaction", "timestamp"),
                    ("ts_database_transaction", "timestamp"),
                ],
                count=100,
                sample=[],
            ),
        )
        self.assertEqual(result.status, "PASS")
        self.assertTrue(result.schema_match)

    def test_sample_ignores_cdc_columns(self) -> None:
        ok, diffs, _ = compare_sample(
            [{"id": 1, "op_cdc": "c", "ts_cdc_transaction": "a"}],
            [{"id": 1, "op_cdc": "u", "ts_cdc_transaction": "b"}],
            ["op_cdc", "ts_cdc_transaction", "ts_database_transaction"],
        )
        self.assertTrue(ok)
        self.assertEqual(diffs, [])


if __name__ == "__main__":
    unittest.main()
