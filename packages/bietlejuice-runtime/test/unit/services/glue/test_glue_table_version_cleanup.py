"""Unit tests for Glue table version cleanup sweep logic."""

import os
from unittest.mock import MagicMock, patch

import pytest

from bietlejuice.clients.db_clients.glue_client import GlueClient
from bietlejuice.services.glue.glue_table_version_cleanup import (
    GLUE_TABLE_VERSION_CLEANUP_DRY_RUN_ENV,
    GlueTableVersionCleanupService,
    create_glue_client,
    parse_bool_flag,
    resolve_dry_run,
    sweep_glue_table_versions,
    version_ids_to_prune,
)


class TestVersionIdsToPrune:
    @pytest.mark.parametrize(
        ("version_ids", "keep_count", "expected"),
        [
            (["1", "2", "3"], 1, ["1", "2"]),
            (["1", "2", "3"], 2, ["1"]),
            (["1", "2"], 1, ["1"]),
            (["1"], 1, []),
            ([], 1, []),
        ],
    )
    def test_prune_keeps_newest_versions(self, version_ids, keep_count, expected):
        assert version_ids_to_prune(version_ids, keep_count) == expected

    def test_keep_count_must_be_positive(self):
        with pytest.raises(ValueError, match="keep_count"):
            version_ids_to_prune(["1", "2"], 0)


class TestSweepGlueTableVersions:
    def _mock_boto_glue(self):
        glue = MagicMock()
        glue.get_paginator.side_effect = self._paginator_factory
        return glue

    def _paginator_factory(self, operation_name):
        paginator = MagicMock()
        if operation_name == "get_databases":
            paginator.paginate.return_value = [
                {"DatabaseList": [{"Name": "datalake_example"}]}
            ]
        elif operation_name == "get_tables":
            paginator.paginate.return_value = [
                {"TableList": [{"Name": "events"}, {"Name": "users"}]}
            ]
        elif operation_name == "get_table_versions":
            paginator.paginate.return_value = [
                {
                    "TableVersions": [
                        {"VersionId": "100"},
                        {"VersionId": "200"},
                        {"VersionId": "300"},
                    ]
                }
            ]
        else:
            raise AssertionError(f"unexpected paginator {operation_name}")
        return paginator

    def test_dry_run_counts_versions_without_deleting(self):
        glue = self._mock_boto_glue()

        summary = sweep_glue_table_versions(glue, dry_run=True)

        assert summary.databases_scanned == 1
        assert summary.tables_scanned == 2
        assert summary.tables_with_prunable_versions == 2
        assert summary.versions_would_delete == 4
        assert summary.versions_deleted == 0
        glue.batch_delete_table_version.assert_not_called()

    def test_live_run_deletes_old_versions_in_batches(self):
        glue = self._mock_boto_glue()
        glue.batch_delete_table_version.return_value = {"Errors": []}

        summary = sweep_glue_table_versions(glue, dry_run=False)

        assert summary.versions_deleted == 4
        assert glue.batch_delete_table_version.call_count == 2
        first_call = glue.batch_delete_table_version.call_args_list[0][1]
        assert first_call["DatabaseName"] == "datalake_example"
        assert first_call["TableName"] == "events"
        assert first_call["VersionIds"] == ["100", "200"]

    def test_database_prefix_filters_databases(self):
        glue = MagicMock()
        databases_paginator = MagicMock()
        databases_paginator.paginate.return_value = [
            {
                "DatabaseList": [
                    {"Name": "datalake_a"},
                    {"Name": "other_b"},
                ]
            }
        ]
        tables_paginator = MagicMock()
        tables_paginator.paginate.return_value = [{"TableList": [{"Name": "t1"}]}]
        versions_paginator = MagicMock()
        versions_paginator.paginate.return_value = [{"TableVersions": []}]

        def paginator_side_effect(operation_name):
            if operation_name == "get_databases":
                return databases_paginator
            if operation_name == "get_tables":
                return tables_paginator
            if operation_name == "get_table_versions":
                return versions_paginator
            raise AssertionError(operation_name)

        glue.get_paginator.side_effect = paginator_side_effect

        summary = sweep_glue_table_versions(
            glue, database_prefix="datalake_", dry_run=True
        )

        assert summary.databases_scanned == 1
        assert summary.tables_scanned == 1

    def test_max_tables_stops_early(self):
        glue = self._mock_boto_glue()

        summary = sweep_glue_table_versions(glue, dry_run=True, max_tables=1)

        assert summary.tables_scanned == 1

    def test_service_raises_when_fail_on_error_and_failures_exist(self):
        glue_client = MagicMock(spec=GlueClient)
        glue_client.get_database_names.return_value = ["datalake_example"]
        glue_client.get_table_names.return_value = ["events"]
        glue_client.list_table_version_ids.return_value = ["1", "2"]
        glue_client.batch_delete_table_versions.side_effect = RuntimeError("boom")

        service = GlueTableVersionCleanupService()
        with pytest.raises(RuntimeError, match="failed for 1 table"):
            service.sweep(glue_client, dry_run=False, fail_on_error=True)

    def test_service_returns_summary_when_fail_on_error_false(self):
        glue_client = MagicMock(spec=GlueClient)
        glue_client.get_database_names.return_value = ["datalake_example"]
        glue_client.get_table_names.return_value = ["events"]
        glue_client.list_table_version_ids.return_value = ["1", "2"]
        glue_client.batch_delete_table_versions.side_effect = RuntimeError("boom")

        service = GlueTableVersionCleanupService()
        summary = service.sweep(glue_client, dry_run=False, fail_on_error=False)

        assert len(summary.failures) == 1
        assert summary.failures[0][0] == "datalake_example.events"


class TestCreateGlueClient:
    @patch("bietlejuice.services.glue.glue_table_version_cleanup.GlueClient")
    def test_create_glue_client_passes_explicit_role_arn(self, mock_glue_client_cls):
        role_arn = "arn:aws:iam::111111111111:role/glue-maintenance"
        create_glue_client(role_arn=role_arn, region="us-west-2")
        mock_glue_client_cls.assert_called_once_with(
            role_arn=role_arn,
            region="us-west-2",
        )

    @patch.dict(
        "os.environ", {"GLUE_ASSUME_ROLE_ARN": "arn:aws:iam::222:role/from-env"}
    )
    @patch("bietlejuice.services.glue.glue_table_version_cleanup.GlueClient")
    def test_create_glue_client_reads_env_when_role_not_passed(
        self, mock_glue_client_cls
    ):
        create_glue_client()
        mock_glue_client_cls.assert_called_once_with(
            role_arn="arn:aws:iam::222:role/from-env",
            region="us-east-1",
        )

    @patch(
        "bietlejuice.services.glue.glue_table_version_cleanup.create_glue_boto_client"
    )
    def test_create_glue_client_uses_worker_role_only(self, mock_boto_client):
        worker = "arn:aws:iam::206390561754:role/airflow-prod-role"
        create_glue_client(worker_role_arn=worker)
        mock_boto_client.assert_called_once_with(
            role_arn=None,
            worker_role_arn=worker,
            region="us-east-1",
        )

    @patch(
        "bietlejuice.services.glue.glue_table_version_cleanup.create_glue_boto_client"
    )
    def test_create_glue_client_chains_when_both_roles_explicit(self, mock_boto_client):
        worker = "arn:aws:iam::206390561754:role/airflow-prod-role"
        glue = "arn:aws:iam::206390561754:role/databricks-prod-glue-access"
        create_glue_client(role_arn=glue, worker_role_arn=worker)
        mock_boto_client.assert_called_once_with(
            role_arn=glue,
            worker_role_arn=worker,
            region="us-east-1",
        )


class TestCreateGlueBotoClient:
    @patch("bietlejuice.services.glue.glue_table_version_cleanup.boto3")
    def test_worker_only_does_not_read_glue_assume_env(self, mock_boto3):
        from bietlejuice.services.glue.glue_table_version_cleanup import (
            create_glue_boto_client,
        )

        base_session = MagicMock()
        worker_session = MagicMock()
        mock_boto3.Session.side_effect = [base_session, worker_session]
        base_session.client.return_value.assume_role.return_value = {
            "Credentials": {
                "AccessKeyId": "ak",
                "SecretAccessKey": "sk",
                "SessionToken": "tok",
            }
        }
        worker = "arn:aws:iam::206390561754:role/airflow-prod-role"

        with patch.dict(
            os.environ,
            {"GLUE_ASSUME_ROLE_ARN": "arn:aws:iam::206390561754:role/should-not-use"},
        ):
            create_glue_boto_client(worker_role_arn=worker)

        assert mock_boto3.Session.call_count == 2
        worker_session.client.assert_called_once_with("glue")
        assert base_session.client.return_value.assume_role.call_count == 1
        base_session.client.return_value.assume_role.assert_called_once_with(
            RoleArn=worker,
            RoleSessionName="airflow-glue-table-version-cleanup",
            DurationSeconds=3600,
        )


class TestDryRunFeatureFlag:
    def test_resolve_dry_run_uses_env_when_conf_missing(self):
        with patch.dict(os.environ, {GLUE_TABLE_VERSION_CLEANUP_DRY_RUN_ENV: "true"}):
            assert resolve_dry_run() is True

    def test_resolve_dry_run_conf_overrides_env(self):
        with patch.dict(os.environ, {GLUE_TABLE_VERSION_CLEANUP_DRY_RUN_ENV: "true"}):
            assert resolve_dry_run(conf_value=False, conf_key_present=True) is False

    def test_resolve_dry_run_param_used_when_conf_and_env_missing(self):
        assert resolve_dry_run(param_value=True, param_key_present=True) is True

    def test_resolve_dry_run_env_overrides_param(self):
        with patch.dict(os.environ, {GLUE_TABLE_VERSION_CLEANUP_DRY_RUN_ENV: "true"}):
            assert resolve_dry_run(param_value=False, param_key_present=True) is True

    def test_parse_bool_flag_accepts_common_truthy_values(self):
        assert parse_bool_flag("yes") is True
        assert parse_bool_flag("off") is False
