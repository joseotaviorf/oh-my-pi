"""Tests for CLI defaults (skip sample by default)."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest import mock

SKILL_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL_DIR))

import batch_validate
import validate


class TestCliDefaults(unittest.TestCase):
    def test_validate_default_skips_sample(self) -> None:
        with mock.patch.object(sys, "argv", ["validate.py", "--dag", "my_dag", "--domain", "fintech"]):
            args = validate.parse_args()
            args.skip_sample = not args.with_sample
            args.skip_profile = args.no_profile
        self.assertFalse(args.with_sample)
        self.assertTrue(args.skip_sample)
        self.assertFalse(args.no_profile)

    def test_validate_no_profile_disables_profile(self) -> None:
        with mock.patch.object(
            sys,
            "argv",
            ["validate.py", "--dag", "my_dag", "--domain", "fintech", "--no-profile"],
        ):
            args = validate.parse_args()
            args.skip_profile = args.no_profile
        self.assertTrue(args.no_profile)
        self.assertTrue(args.skip_profile)

    def test_validate_with_sample_enables_sample(self) -> None:
        with mock.patch.object(
            sys,
            "argv",
            ["validate.py", "--dag", "my_dag", "--domain", "fintech", "--with-sample"],
        ):
            args = validate.parse_args()
            args.skip_sample = not args.with_sample
        self.assertTrue(args.with_sample)
        self.assertFalse(args.skip_sample)

    def test_batch_validate_default_skips_sample(self) -> None:
        with mock.patch.object(
            sys,
            "argv",
            ["batch_validate.py", "--line", "fintech", "--phase", "watch", "--run-id", "abc"],
        ):
            args = batch_validate.parse_args()
            args.skip_sample = not args.with_sample
        self.assertFalse(args.with_sample)
        self.assertTrue(args.skip_sample)


if __name__ == "__main__":
    unittest.main()
