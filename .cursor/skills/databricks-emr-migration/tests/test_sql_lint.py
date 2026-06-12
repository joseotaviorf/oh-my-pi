"""Tests for SQL lint and translation discovery."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SKILL_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL_DIR))

import sql_lint


class TestSqlLint(unittest.TestCase):
    def test_read_sql_from_git_falls_back_to_working_tree(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo_root = Path(tmp)
            sql_path = (
                repo_root
                / "dags/fintech/dw_x/queries/dw/new_table.sql"
            )
            sql_path.parent.mkdir(parents=True)
            sql_path.write_text("SELECT IFF(1, 1, 0)", encoding="utf-8")

            with mock.patch.object(
                sql_lint.subprocess,
                "run",
                return_value=mock.Mock(returncode=128, stdout="", stderr="path not in master"),
            ):
                sql = sql_lint.read_sql_from_git(
                    "fintech",
                    "dw_x",
                    "dw",
                    "new_table",
                    "master",
                    repo_root=repo_root,
                )

            self.assertIn("IFF", sql)

    def test_discover_tables_needing_translation_includes_branch_only_sql(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo_root = Path(tmp)
            sql_path = (
                repo_root
                / "dags/fintech/dw_x/queries/dw/new_table.sql"
            )
            sql_path.parent.mkdir(parents=True)
            sql_path.write_text("SELECT IFF(1, 1, 0)", encoding="utf-8")

            with mock.patch.object(
                sql_lint.subprocess,
                "run",
                return_value=mock.Mock(returncode=128, stdout="", stderr="path not in master"),
            ):
                translated, skipped = sql_lint.discover_tables_needing_translation(
                    "fintech",
                    "dw_x",
                    "master",
                    repo_root=repo_root,
                )

            self.assertEqual(translated, [("new_table", "dw")])
            self.assertEqual(skipped, [])


if __name__ == "__main__":
    unittest.main()
