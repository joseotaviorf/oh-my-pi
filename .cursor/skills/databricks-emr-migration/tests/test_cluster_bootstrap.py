"""Tests for EMR cluster reuse and describe-cluster error handling."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest import mock

SKILL_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL_DIR))

import cluster_bootstrap as cluster_module


class TestClusterBootstrap(unittest.TestCase):
    def test_is_emr_cluster_reusable_does_not_clear_session_on_describe_failure(
        self,
    ) -> None:
        with (
            mock.patch.object(
                cluster_module,
                "describe_emr_cluster",
                side_effect=RuntimeError("ExpiredToken"),
            ),
            mock.patch.object(cluster_module, "clear_session_emr_cluster") as clear_session,
        ):
            reusable, state = cluster_module.is_emr_cluster_reusable("j-ABC123")

        self.assertFalse(reusable)
        self.assertEqual(state, "UNAVAILABLE")
        clear_session.assert_not_called()

    def test_is_emr_cluster_reusable_clears_session_only_for_dead_states(self) -> None:
        with (
            mock.patch.object(
                cluster_module,
                "describe_emr_cluster",
                return_value="TERMINATED",
            ),
            mock.patch.object(cluster_module, "clear_session_emr_cluster") as clear_session,
        ):
            reusable, state = cluster_module.is_emr_cluster_reusable("j-ABC123")

        self.assertFalse(reusable)
        self.assertEqual(state, "TERMINATED")
        clear_session.assert_called_once_with("j-ABC123")

    def test_resolve_databricks_cluster_requires_explicit_id(self) -> None:
        with self.assertRaises(RuntimeError) as ctx:
            cluster_module.resolve_databricks_cluster(None, "PROD")
        self.assertIn("required", str(ctx.exception).lower())

    def test_resolve_databricks_cluster_rejects_blank_id(self) -> None:
        with self.assertRaises(RuntimeError):
            cluster_module.resolve_databricks_cluster("   ", "PROD")

    def test_resolve_validation_emr_cluster_reuses_session_without_new_session(
        self,
    ) -> None:
        session_cluster = "j-35ZDQQ6OQIL3T"
        with (
            mock.patch.object(cluster_module, "ensure_aws_credentials"),
            mock.patch.object(
                cluster_module,
                "load_session",
                return_value={"emr_cluster_id": session_cluster},
            ),
            mock.patch.object(cluster_module, "save_session"),
            mock.patch.object(
                cluster_module,
                "is_migration_validation_cluster",
                return_value=True,
            ),
            mock.patch.object(
                cluster_module,
                "is_emr_cluster_reusable",
                return_value=(True, "WAITING"),
            ),
            mock.patch.object(cluster_module, "create_emr_cluster") as create_cluster,
        ):
            resolved = cluster_module.resolve_validation_emr_cluster(
                None,
                new_session=False,
            )

        self.assertEqual(resolved, session_cluster)
        create_cluster.assert_not_called()


if __name__ == "__main__":
    unittest.main()
