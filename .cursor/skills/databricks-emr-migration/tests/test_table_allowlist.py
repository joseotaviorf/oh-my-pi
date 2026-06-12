"""Tests for layer-scoped table allowlist in compare mode."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest import mock

SKILL_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL_DIR))

import validate as validate_module
from baseline import baseline_lookup_key, tables_needing_baseline


class TestTableAllowlist(unittest.TestCase):
    def test_resolve_table_allowlist_preserves_layer(self) -> None:
        args = mock.Mock(
            all_tables=False,
            phase="compare",
            table=None,
            domain="fintech",
            dag="dw_credit_analysis",
        )
        with mock.patch.object(
            validate_module,
            "discover_tables_needing_translation",
            return_value=(
                [("shared_name", "dw")],
                [("shared_name", "enrich")],
            ),
        ):
            allowlist, skipped = validate_module._resolve_table_allowlist(
                args,
                "master",
                Path("/repo"),
            )

        self.assertEqual(allowlist, {("dw", "shared_name")})
        self.assertEqual(skipped, ["enrich/shared_name"])

    def test_tables_needing_baseline_filters_by_layer_not_stem(self) -> None:
        with (
            mock.patch(
                "baseline.discover_tables",
                return_value=[
                    ("shared_name", "dw"),
                    ("shared_name", "enrich"),
                ],
            ),
            mock.patch(
                "baseline.load_baseline_for_table",
                return_value=None,
            ),
        ):
            needing = tables_needing_baseline(
                "fintech",
                "dw_credit_analysis",
                "2026-06-04",
                "2026-06-05",
                table_allowlist={baseline_lookup_key("dw", "shared_name")},
            )

        self.assertEqual(needing, [("shared_name", "dw")])

    def test_resolve_table_allowlist_single_table_includes_all_layers(self) -> None:
        args = mock.Mock(
            all_tables=False,
            phase="compare",
            table="dim_x",
            domain="fintech",
            dag="dw_credit_analysis",
        )
        with mock.patch.object(
            validate_module,
            "discover_tables",
            return_value=[
                ("dim_x", "dw"),
                ("dim_x", "metric"),
            ],
        ):
            allowlist, skipped = validate_module._resolve_table_allowlist(
                args,
                "master",
                Path("/repo"),
            )

        self.assertEqual(
            allowlist,
            {("dw", "dim_x"), ("metric", "dim_x")},
        )
        self.assertEqual(skipped, [])


if __name__ == "__main__":
    unittest.main()
