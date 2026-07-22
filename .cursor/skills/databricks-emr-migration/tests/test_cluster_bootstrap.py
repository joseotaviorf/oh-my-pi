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

    def test_job_flow_role_for_people_domain(self) -> None:
        self.assertEqual(
            cluster_module.job_flow_role_for_domain("people"),
            "emr-people-prod",
        )
        self.assertEqual(
            cluster_module.job_flow_role_for_domain("People"),
            "emr-people-prod",
        )
        self.assertEqual(
            cluster_module.job_flow_role_for_domain("fintech"),
            "emr-prod",
        )
        self.assertEqual(cluster_module.job_flow_role_for_domain(None), "emr-prod")

    def test_domain_tag_for_people_domain(self) -> None:
        self.assertEqual(cluster_module.domain_tag_for_domain("people"), "people")
        self.assertEqual(cluster_module.domain_tag_for_domain("fintech"), "default")

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
                "cluster_matches_domain",
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
                domain="fintech",
            )

        self.assertEqual(resolved, session_cluster)
        create_cluster.assert_not_called()

    def test_resolve_skips_cluster_with_mismatched_domain_and_creates_people(
        self,
    ) -> None:
        session_cluster = "j-DEFAULTCLUSTER"
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
                "cluster_matches_domain",
                return_value=False,
            ),
            mock.patch.object(
                cluster_module,
                "cluster_domain_tag",
                return_value="default",
            ),
            mock.patch.object(
                cluster_module,
                "find_emr_clusters_by_tag",
                return_value=[],
            ),
            mock.patch.object(
                cluster_module,
                "create_emr_cluster",
                return_value="j-PEOPLECLUSTER",
            ) as create_cluster,
        ):
            resolved = cluster_module.resolve_validation_emr_cluster(
                None,
                new_session=False,
                domain="people",
            )

        self.assertEqual(resolved, "j-PEOPLECLUSTER")
        create_cluster.assert_called_once_with("prod", domain="people")

    def test_create_emr_cluster_passes_people_job_flow_role(self) -> None:
        with (
            mock.patch.object(
                cluster_module,
                "run_emr_cli",
                return_value=(0, "Created cluster j-PEOPLE123"),
            ) as run_cli,
            mock.patch.object(cluster_module, "_wait_for_emr_cluster"),
        ):
            cluster_id = cluster_module.create_emr_cluster("prod", domain="people")

        self.assertEqual(cluster_id, "j-PEOPLE123")
        args = run_cli.call_args[0][0]
        self.assertIn("--job-flow-role", args)
        self.assertEqual(args[args.index("--job-flow-role") + 1], "emr-people-prod")
        self.assertIn("Domain=people", args)
        self.assertIn("JobFlowRole=emr-people-prod", args)

    def test_cluster_matches_domain_false_when_describe_fails(self) -> None:
        with mock.patch.object(
            cluster_module,
            "describe_cluster_json",
            side_effect=RuntimeError("ExpiredToken"),
        ):
            self.assertIsNone(cluster_module.cluster_domain_tag("j-ABC"))
            self.assertFalse(cluster_module.cluster_matches_domain("j-ABC", "fintech"))
            self.assertFalse(cluster_module.cluster_matches_domain("j-ABC", "people"))

    def test_resolve_scans_all_tagged_clusters_for_domain_match(self) -> None:
        with (
            mock.patch.object(cluster_module, "ensure_aws_credentials"),
            mock.patch.object(cluster_module, "load_session", return_value={}),
            mock.patch.object(cluster_module, "save_session"),
            mock.patch.object(
                cluster_module,
                "find_emr_clusters_by_tag",
                return_value=["j-DEFAULT", "j-PEOPLE"],
            ),
            mock.patch.object(
                cluster_module,
                "is_migration_validation_cluster",
                return_value=True,
            ),
            mock.patch.object(
                cluster_module,
                "cluster_matches_domain",
                side_effect=lambda cid, domain, region="us-east-1": cid == "j-PEOPLE",
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
                domain="people",
            )

        self.assertEqual(resolved, "j-PEOPLE")
        create_cluster.assert_not_called()

    def test_explicit_emr_cluster_domain_mismatch_raises(self) -> None:
        with (
            mock.patch.object(cluster_module, "ensure_aws_credentials"),
            mock.patch.object(cluster_module, "load_session", return_value={}),
            mock.patch.object(
                cluster_module,
                "find_emr_clusters_by_tag",
                return_value=[],
            ),
            mock.patch.object(
                cluster_module,
                "cluster_matches_domain",
                return_value=False,
            ),
            mock.patch.object(
                cluster_module,
                "cluster_domain_tag",
                return_value="default",
            ),
            mock.patch.object(cluster_module, "create_emr_cluster") as create_cluster,
        ):
            with self.assertRaises(RuntimeError) as ctx:
                cluster_module.resolve_validation_emr_cluster(
                    "j-WRONGPROFILE",
                    new_session=False,
                    domain="people",
                )

        self.assertIn("--emr-cluster", str(ctx.exception))
        self.assertIn("Domain=default", str(ctx.exception))
        self.assertIn("Domain=people", str(ctx.exception))
        create_cluster.assert_not_called()


if __name__ == "__main__":
    unittest.main()
