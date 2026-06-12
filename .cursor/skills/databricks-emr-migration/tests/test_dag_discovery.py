import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from dag_discovery import discover_dags_for_line, load_scope_file, parse_scope_pairs
from paths import REPO_ROOT


class TestDagDiscovery(unittest.TestCase):
    def test_discover_fintech_includes_non_emr_dag(self) -> None:
        dags = discover_dags_for_line("fintech", repo_root=REPO_ROOT)
        names = {dag for _, dag in dags}
        self.assertIn("dw_credit_analysis", names)

    def test_emr_only_dag_excluded(self) -> None:
        with patch("dag_discovery._cluster_type", return_value="emr_7_12_min_memory_3_workers_cluster"):
            with patch.object(Path, "is_dir", return_value=True):
                dags = discover_dags_for_line("fintech", repo_root=REPO_ROOT)
        # betopera uses emr_* — should not appear when all cluster types are emr
        self.assertEqual(dags, [])

    def test_parse_scope_pairs(self) -> None:
        pairs = parse_scope_pairs(
            "fintech/dw_credit_analysis,agents/enrich_agent",
            repo_root=REPO_ROOT,
        )
        self.assertEqual(
            pairs,
            [("fintech", "dw_credit_analysis"), ("agents", "enrich_agent")],
        )

    def test_parse_scope_pairs_rejects_invalid_entry(self) -> None:
        with self.assertRaises(ValueError):
            parse_scope_pairs("not_a_valid_scope", repo_root=REPO_ROOT)

    def test_load_scope_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            scope_path = Path(tmp) / "scope.yml"
            scope_path.write_text(
                "- domain: fintech\n  dag: dw_credit_analysis\n",
                encoding="utf-8",
            )
            pairs = load_scope_file(scope_path, repo_root=REPO_ROOT)
            self.assertEqual(pairs, [("fintech", "dw_credit_analysis")])


if __name__ == "__main__":
    unittest.main()
