import shutil
from pathlib import Path
from unittest import mock

import pytest

import bietlejuice.base.service.dag_packages_path_service as dag_packages_path_service
from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser import (
    DAGYamlParser,
)
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.services.file_service import FileService


class TestDAGYAMLParser:
    @mock.patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser.DAGClusterValidator"
    )
    @mock.patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser.DAGDeclarationValidator"
    )
    @mock.patch.object(FileService, "get_dict_from_yaml_file")
    @mock.patch.object(DAGPackagesPathService, "resolve_artifact_file_path")
    @mock.patch.object(DAGPackagesPathService, "generate_artifact_file_path")
    def test_dag_declaration(
        self,
        mocked_generate_artifact_file_path,
        mocked_resolve_artifact_file_path,
        mocked_get_dict_from_yaml_file,
        mocked_dag_declaration_validator,
        mocked_dag_cluster_validator,
        dag_yaml_parser,
    ):
        decl_path = "dag/declaration/path.yml"
        cluster_path = "dag/cluster/path.yaml"
        expected_cluster_base = "dag/cluster/path"
        mocked_generate_artifact_file_path.side_effect = [
            decl_path,
            expected_cluster_base,
        ]
        mocked_resolve_artifact_file_path.return_value = cluster_path

        declaration = {"dag": {"a": 1}, "workflow": {"b": 2}}
        cluster_file_body = {
            "cluster": {
                "type": "c",
                "access_control_list": {
                    "group_name": "admins",
                    "permission_level": "CAN_MANAGE",
                },
            }
        }
        merged = {**declaration, "cluster": cluster_file_body["cluster"]}
        mocked_get_dict_from_yaml_file.side_effect = [declaration, cluster_file_body]

        returned_value = dag_yaml_parser.dag_declaration()

        assert returned_value == merged
        assert mocked_generate_artifact_file_path.call_args_list == [
            mock.call(artifact_type="dag_declaration", dag_name=""),
            mock.call(artifact_type="dag_cluster", dag_name="", add_default_ext=False),
        ]
        mocked_resolve_artifact_file_path.assert_called_once_with(
            artifact_type="dag_cluster", dag_name=""
        )
        assert mocked_get_dict_from_yaml_file.call_args_list == [
            mock.call(decl_path),
            mock.call(cluster_path),
        ]
        mocked_dag_declaration_validator.assert_called_once()
        mocked_dag_declaration_validator().validate.assert_called_once_with(
            dag_declaration=declaration
        )
        mocked_dag_cluster_validator.assert_called_once()
        mocked_dag_cluster_validator().validate_cluster.assert_called_once_with(
            dag_declaration=merged
        )

    @mock.patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser.DAGDeclarationValidator"
    )
    @mock.patch.object(FileService, "get_dict_from_yaml_file")
    @mock.patch.object(DAGPackagesPathService, "resolve_artifact_file_path")
    @mock.patch.object(DAGPackagesPathService, "generate_artifact_file_path")
    def test_empty_cluster_file_raises_assertion_error(
        self,
        mocked_generate_artifact_file_path,
        mocked_resolve_artifact_file_path,
        mocked_get_dict_from_yaml_file,
        mocked_dag_declaration_validator,
        dag_yaml_parser,
    ):
        decl_path = "dag/declaration/path.yml"
        cluster_path = "dag/cluster/path.yml"
        mocked_generate_artifact_file_path.return_value = decl_path
        mocked_resolve_artifact_file_path.return_value = cluster_path
        mocked_get_dict_from_yaml_file.side_effect = [
            {"dag": {"a": 1}, "workflow": {"b": 2}},
            None,
        ]

        with pytest.raises(AssertionError, match="YAML mapping"):
            dag_yaml_parser.dag_declaration()

        mocked_dag_declaration_validator().validate.assert_called_once()

    def test_non_existent_dag(self, dag_yaml_parser):
        # arrange
        dag_name = "non_existent_dag"
        dag_yaml_parser._DAGYamlParser__dag_name = dag_name

        # act & assert
        with pytest.raises(FileNotFoundError):
            dag_yaml_parser.dag_declaration()

    def test_dag_declaration_loads_valid_yaml_from_disk(self, monkeypatch, tmp_path):
        """Integration: real YAML files, both validators, merged result.

        Static fixtures under ``fixtures/``; tree under ``tmp_path`` with
        ``DAG_PACKAGES_ROOT`` redirected. ``clear_path_caches`` avoids leaking
        ``get_dag_path`` entries.
        """
        dag_name = "minimal"
        line = "platform"
        decl_name = f"{dag_name}_declaration.yml"
        cluster_name = f"{dag_name}_cluster.yml"
        fixtures_dir = Path(__file__).resolve().parent / "fixtures"
        assert (fixtures_dir / decl_name).is_file(), f"Missing {decl_name}"
        assert (fixtures_dir / cluster_name).is_file(), f"Missing {cluster_name}"
        dag_dir = tmp_path / line / dag_name
        dag_dir.mkdir(parents=True)
        shutil.copy(fixtures_dir / decl_name, dag_dir / decl_name)
        shutil.copy(fixtures_dir / cluster_name, dag_dir / cluster_name)

        monkeypatch.setattr(
            dag_packages_path_service, "DAG_PACKAGES_ROOT", str(tmp_path)
        )
        DAGPackagesPathService.clear_path_caches()
        try:
            result = DAGYamlParser(dag_name=dag_name).dag_declaration()
        finally:
            DAGPackagesPathService.clear_path_caches()

        assert result["dag"]["name"] == dag_name
        assert result["dag"]["owner"] == "Data Engineering"
        assert result["workflow"]["type"] == "query"
        assert result["workflow"]["layer"] == "dw"
        # Cluster shape and ACL rules are covered in test_dag_cluster_validator; here we
        # only assert merge + successful validation of the real fixtures.
        assert result["cluster"]["type"] == "databricks_16_4_med_general_cluster"

    def test_dag_declaration_loads_cluster_yaml_extension_from_disk(
        self, monkeypatch, tmp_path
    ):
        dag_name = "minimal"
        line = "platform"
        decl_name = f"{dag_name}_declaration.yml"
        cluster_name = f"{dag_name}_cluster.yaml"
        fixtures_dir = Path(__file__).resolve().parent / "fixtures"
        dag_dir = tmp_path / line / dag_name
        dag_dir.mkdir(parents=True)
        shutil.copy(fixtures_dir / decl_name, dag_dir / decl_name)
        shutil.copy(fixtures_dir / f"{dag_name}_cluster.yml", dag_dir / cluster_name)

        monkeypatch.setattr(
            dag_packages_path_service, "DAG_PACKAGES_ROOT", str(tmp_path)
        )
        DAGPackagesPathService.clear_path_caches()
        try:
            result = DAGYamlParser(dag_name=dag_name).dag_declaration()
        finally:
            DAGPackagesPathService.clear_path_caches()

        assert result["cluster"]["type"] == "databricks_16_4_med_general_cluster"
