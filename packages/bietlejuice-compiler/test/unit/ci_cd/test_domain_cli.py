import argparse
import unittest

from scripts.ci_cd.domain_cli import (
    branch_name_arg_type,
    domain_arg_type,
    repo_relative_file_arg_type,
    source_layer_profile_arg_type,
)


class DomainArgTypeTest(unittest.TestCase):
    def test_accepts_typical_domain(self) -> None:
        self.assertEqual(domain_arg_type("for_rent"), "for_rent")
        self.assertEqual(domain_arg_type("broker_xp"), "broker_xp")
        self.assertEqual(domain_arg_type("growth"), "growth")

    def test_rejects_traversal(self) -> None:
        with self.assertRaises(argparse.ArgumentTypeError):
            domain_arg_type("../etc/passwd")

    def test_rejects_slash(self) -> None:
        with self.assertRaises(argparse.ArgumentTypeError):
            domain_arg_type("foo/bar")


class RepoRelativeFileArgTypeTest(unittest.TestCase):
    def test_accepts_dags_path(self) -> None:
        self.assertEqual(
            repo_relative_file_arg_type("dags/for_rent/foo/metadata/raw/x.yml"),
            "dags/for_rent/foo/metadata/raw/x.yml",
        )

    def test_rejects_dotdot(self) -> None:
        with self.assertRaises(argparse.ArgumentTypeError):
            repo_relative_file_arg_type("dags/foo/../../../etc/passwd")


class BranchNameArgTypeTest(unittest.TestCase):
    def test_empty_allowed(self) -> None:
        self.assertEqual(branch_name_arg_type(""), "")

    def test_feature_branch(self) -> None:
        self.assertEqual(branch_name_arg_type("feat/foo-bar_1"), "feat/foo-bar_1")


class ProfileArgTypeTest(unittest.TestCase):
    def test_dags(self) -> None:
        self.assertEqual(source_layer_profile_arg_type("dags"), "dags")


if __name__ == "__main__":
    unittest.main()
