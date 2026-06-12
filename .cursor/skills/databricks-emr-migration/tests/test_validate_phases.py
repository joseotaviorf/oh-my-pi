import unittest
from unittest.mock import MagicMock, patch

import validate as validate_module


class TestValidatePhases(unittest.TestCase):
    def test_watch_requires_run_id(self) -> None:
        with patch.object(validate_module, "load_session", return_value={}):
            with patch.object(
                validate_module,
                "parse_args",
                return_value=MagicMock(
                    phase="watch",
                    run_id=None,
                    domain="fintech",
                    dag=None,
                    emr_env="prod",
                    poll_interval=15,
                    job_timeout=3600,
                    global_timeout=None,
                    skip_sample=False,
                ),
            ):
                self.assertEqual(validate_module.main(), 1)

    def test_compare_requires_cluster(self) -> None:
        args = MagicMock(
            phase="compare",
            sync=False,
            dag="dw_x",
            domain="fintech",
            cluster=None,
            profile="PROD",
            emr_cluster=None,
            emr_env="prod",
            staging_uri=None,
            skip_sample=False,
            timeout=300,
            table=None,
            no_create_emr=False,
            new_emr_session=False,
            run_id=None,
            max_parallel=5,
            git_ref=None,
            verbose=False,
            all_tables=False,
        )
        with patch.object(validate_module, "parse_args", return_value=args):
            self.assertEqual(validate_module.main(), 1)

    def test_submit_phase_returns_zero(self) -> None:
        args = MagicMock(
            phase="submit",
            sync=False,
            dag="dw_x",
            domain="fintech",
            cluster="c1",
            profile="PROD",
            emr_cluster=None,
            emr_env="prod",
            staging_uri=None,
            skip_sample=False,
            timeout=300,
            table=None,
            no_create_emr=False,
            new_emr_session=False,
            run_id=None,
            max_parallel=5,
            git_ref=None,
            verbose=False,
            all_tables=False,
        )
        with patch.object(validate_module, "parse_args", return_value=args):
            with patch.object(validate_module, "_resolve_table_allowlist", return_value=({("dw", "t")}, [])):
                with patch.object(validate_module, "_run_async_submit", return_value="run123"):
                    with patch.object(validate_module, "validate_cli_args"):
                        with patch.object(validate_module, "validate_iso_date"):
                            self.assertEqual(validate_module.main(), 0)


if __name__ == "__main__":
    unittest.main()
