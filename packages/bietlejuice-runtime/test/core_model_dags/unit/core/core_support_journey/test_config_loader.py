"""Unit tests for support journey table spec config loading."""

from types import SimpleNamespace
from unittest import mock

import pytest
import yaml

from bietlejuice.base.sst.domains.salesforce.core_models import config_loader


class TestLoadTableSpecFromRelativePath:
    @mock.patch.object(config_loader.DAGPackagesPathService, "_read_file_from_s3_boto3")
    @mock.patch.object(config_loader, "_artifacts_bucket_name")
    def test_reads_from_astronomer_dags_on_artifacts_bucket(
        self, mock_bucket_name, mock_read_s3
    ):
        mock_bucket_name.return_value = "artifacts.s3.forno.data.quintoandar.com.br"
        spec = {"target_table": "cases", "merge_on": ["id_event"]}
        mock_read_s3.return_value = yaml.dump(spec)

        result = config_loader.load_table_spec_from_relative_path(
            "core/core_support_journey/tables/cases.yml"
        )

        assert result == spec
        mock_read_s3.assert_called_once_with(
            "artifacts.s3.forno.data.quintoandar.com.br",
            "astronomer/dags/core/core_support_journey/tables/cases.yml",
        )

    @mock.patch.object(config_loader.DAGPackagesPathService, "_read_file_from_s3_boto3")
    @mock.patch.object(config_loader, "_artifacts_bucket_name")
    def test_raises_when_object_missing(self, mock_bucket_name, mock_read_s3):
        mock_bucket_name.return_value = "artifacts.s3.data.quintoandar.com.br"
        mock_read_s3.return_value = ""

        with pytest.raises(FileNotFoundError, match="upload-dag-packages-dags-s3"):
            config_loader.load_table_spec_from_relative_path(
                "core/core_support_journey/tables/cases.yml"
            )


class TestTableSpecFromCfg:
    @mock.patch.object(config_loader, "load_table_spec_from_relative_path")
    def test_prefers_relative_path(self, mock_load):
        mock_load.return_value = {"target_table": "cases"}
        cfg = SimpleNamespace(
            table_config_relative_path="core/core_support_journey/tables/cases.yml"
        )

        assert config_loader.table_spec_from_cfg(cfg) == {"target_table": "cases"}
        mock_load.assert_called_once_with("core/core_support_journey/tables/cases.yml")

    def test_falls_back_to_json_dict(self):
        spec = {"target_table": "cases"}
        cfg = SimpleNamespace(table_config_json=spec)

        assert config_loader.table_spec_from_cfg(cfg) == spec
