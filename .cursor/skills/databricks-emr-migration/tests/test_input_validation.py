import sys
import unittest
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL_DIR))

from input_validation import (
    InputValidationError,
    format_order_by_clause,
    validate_cli_args,
    validate_git_ref,
    validate_order_by_column,
    validate_resource_name,
)
from query_builders import build_count_query, build_sample_query


class InputValidationTests(unittest.TestCase):
    def test_validate_resource_name_accepts_snake_case(self) -> None:
        self.assertEqual(validate_resource_name("enrich_intune", "dag"), "enrich_intune")
        self.assertEqual(
            validate_resource_name("tech_platform", "domain"),
            "tech_platform",
        )

    def test_validate_resource_name_rejects_injection(self) -> None:
        with self.assertRaises(InputValidationError):
            validate_resource_name("foo; DROP TABLE x", "dag")

    def test_validate_git_ref(self) -> None:
        self.assertEqual(validate_git_ref("master"), "master")
        self.assertEqual(validate_git_ref("origin/main"), "origin/main")
        with self.assertRaises(InputValidationError):
            validate_git_ref("master; evil")

    def test_validate_cli_args(self) -> None:
        validate_cli_args(dag="enrich_intune", domain="tech_platform")
        validate_cli_args(
            dag="dw_credit_analysis",
            domain="fintech",
            table="dim_drop_reason",
            git_ref="master",
        )
        with self.assertRaises(InputValidationError):
            validate_cli_args(dag="bad name", domain="fintech")

    def test_validate_order_by_column(self) -> None:
        self.assertEqual(validate_order_by_column("sk_offer"), "sk_offer")
        self.assertEqual(validate_order_by_column("1"), "1")
        with self.assertRaises(InputValidationError):
            validate_order_by_column("sk_offer; DROP TABLE x")

    def test_format_order_by_clause(self) -> None:
        self.assertEqual(
            format_order_by_clause(["sk_offer", "sk_client"]),
            "sk_offer, sk_client",
        )

    def test_query_builders_use_validated_order_by(self) -> None:
        sql = "SELECT 1 AS sk_offer"
        self.assertEqual(
            build_count_query(sql),
            f"SELECT COUNT(*) AS cnt FROM ({sql}) AS t",
        )
        sample_sql = build_sample_query(sql, ["sk_offer"], 100)
        self.assertIn("ORDER BY sk_offer", sample_sql)
        self.assertIn("LIMIT 100", sample_sql)
        with self.assertRaises(InputValidationError):
            build_sample_query(sql, ["evil; drop"], 100)


if __name__ == "__main__":
    unittest.main()
