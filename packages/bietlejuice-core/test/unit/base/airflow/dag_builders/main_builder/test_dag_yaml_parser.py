import os
import shutil
from pathlib import Path
from unittest import mock

import pytest

import bietlejuice.base.service.dag_packages_path_service as dag_packages_path_service
from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser import (
    DAGYamlParser,
    _parse_dag_declaration,
    resolve_validation_block,
)
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.services.file_service import FileService


@pytest.mark.parametrize(
    ("inline", "cluster_file", "expected"),
    [
        (None, None, None),
        ({"cluster": {"type": "inline"}}, None, {"cluster": {"type": "inline"}}),
        (None, {"cluster": {"type": "split"}}, {"cluster": {"type": "split"}}),
        (
            {"cluster": {"type": "inline"}},
            {"cluster": {"type": "split"}},
            {"cluster": {"type": "split"}},
        ),
    ],
)
def test_resolve_validation_block_precedence(inline, cluster_file, expected):
    declaration = {"validation": inline} if inline is not None else {}
    assert resolve_validation_block(declaration, cluster_file) == expected


class TestDAGYAMLParser:
    def setup_method(self):
        _parse_dag_declaration.cache_clear()

    def teardown_method(self):
        _parse_dag_declaration.cache_clear()

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
        validator_instance = mocked_dag_declaration_validator.return_value
        validator_instance.validate.assert_called_once_with(dag_declaration=declaration)
        validator_instance.validate_cluster_validation_cluster_diff.assert_called_once_with(
            dag_declaration=merged
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

        mocked_dag_declaration_validator().validate.assert_not_called()

    @mock.patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser.DAGClusterValidator"
    )
    @mock.patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser.DAGDeclarationValidator"
    )
    @mock.patch.object(FileService, "get_dict_from_yaml_file")
    @mock.patch.object(DAGPackagesPathService, "resolve_artifact_file_path")
    @mock.patch.object(DAGPackagesPathService, "generate_artifact_file_path")
    def test_validation_section_in_cluster_file(
        self,
        mocked_generate_artifact_file_path,
        mocked_resolve_artifact_file_path,
        mocked_get_dict_from_yaml_file,
        mocked_dag_declaration_validator,
        mocked_dag_cluster_validator,
        dag_yaml_parser,
    ):
        """validation: block in *_cluster.yml is merged into the declaration."""
        decl_path = "dag/declaration/path.yml"
        cluster_path = "dag/cluster/path.yml"
        expected_cluster_base = "dag/cluster/path"
        mocked_generate_artifact_file_path.side_effect = [
            decl_path,
            expected_cluster_base,
        ]
        mocked_resolve_artifact_file_path.return_value = cluster_path
        validation_block = {
            "cluster": {"type": "consolidation_s_general_single_node_cluster"}
        }
        declaration = {"dag": {"a": 1}, "workflow": {"b": 2}}
        cluster_file_body = {
            "cluster": {"type": "databricks_16_4_med_general_cluster"},
            "validation": validation_block,
        }
        mocked_get_dict_from_yaml_file.side_effect = [declaration, cluster_file_body]

        result = dag_yaml_parser.dag_declaration()

        assert result["validation"] == validation_block
        validator_instance = mocked_dag_declaration_validator.return_value
        validator_instance.validate.assert_called_once_with(
            dag_declaration={**declaration, "validation": validation_block}
        )

    def test_non_existent_dag(self, dag_yaml_parser):
        dag_name = "non_existent_dag"
        dag_yaml_parser._DAGYamlParser__dag_name = dag_name

        with pytest.raises(FileNotFoundError):
            dag_yaml_parser.dag_declaration()

    @mock.patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser.DAGClusterValidator"
    )
    @mock.patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser.DAGDeclarationValidator"
    )
    @mock.patch.object(FileService, "get_dict_from_yaml_file")
    @mock.patch.object(DAGPackagesPathService, "resolve_artifact_file_path")
    @mock.patch.object(DAGPackagesPathService, "generate_artifact_file_path")
    def test_dag_declaration_cache_is_shared_by_dag_name(
        self,
        mocked_generate_artifact_file_path,
        mocked_resolve_artifact_file_path,
        mocked_get_dict_from_yaml_file,
        mocked_dag_declaration_validator,
        mocked_dag_cluster_validator,
    ):
        decl_path = "dag/declaration/path.yml"
        cluster_path = "dag/cluster/path.yml"
        mocked_generate_artifact_file_path.side_effect = [
            decl_path,
            "dag/cluster/path",
            decl_path,
        ]
        mocked_resolve_artifact_file_path.return_value = cluster_path
        declaration = {"dag": {"a": 1}, "workflow": {"b": 2}}
        cluster_file_body = {"cluster": {"type": "c"}}
        mocked_get_dict_from_yaml_file.side_effect = [declaration, cluster_file_body]

        DAGYamlParser("my_dag").dag_declaration()
        DAGYamlParser("my_dag").dag_declaration()

        assert mocked_generate_artifact_file_path.call_count == 3
        assert mocked_resolve_artifact_file_path.call_count == 2
        assert mocked_get_dict_from_yaml_file.call_count == 2
        mocked_dag_declaration_validator().validate.assert_called_once()
        mocked_dag_cluster_validator().validate_cluster.assert_called_once()

    @mock.patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser._file_content_hash"
    )
    @mock.patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser.DAGClusterValidator"
    )
    @mock.patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser.DAGDeclarationValidator"
    )
    @mock.patch.object(FileService, "get_dict_from_yaml_file")
    @mock.patch.object(DAGPackagesPathService, "resolve_artifact_file_path")
    @mock.patch.object(DAGPackagesPathService, "generate_artifact_file_path")
    def test_dag_declaration_cache_invalidates_when_content_hash_changes(
        self,
        mocked_generate_artifact_file_path,
        mocked_resolve_artifact_file_path,
        mocked_get_dict_from_yaml_file,
        _mocked_dag_declaration_validator,
        _mocked_dag_cluster_validator,
        mocked_file_content_hash,
    ):
        decl_path = "dag/declaration/path.yml"
        cluster_path = "dag/cluster/path.yml"
        mocked_generate_artifact_file_path.side_effect = [
            decl_path,
            "dag/cluster/path",
            decl_path,
            "dag/cluster/path",
        ]
        mocked_resolve_artifact_file_path.return_value = cluster_path
        mocked_file_content_hash.side_effect = [
            "decl-1",
            "cluster-1",
            "decl-2",
            "cluster-1",
        ]
        mocked_get_dict_from_yaml_file.side_effect = [
            {"dag": {"name": "before"}, "workflow": {}},
            {"cluster": {"type": "c"}},
            {"dag": {"name": "after"}, "workflow": {}},
            {"cluster": {"type": "c"}},
        ]

        before = DAGYamlParser("my_dag").dag_declaration()
        after = DAGYamlParser("my_dag").dag_declaration()

        assert before["dag"]["name"] == "before"
        assert after["dag"]["name"] == "after"
        assert mocked_get_dict_from_yaml_file.call_count == 4

    def test_dag_declaration_loads_valid_yaml_from_disk(self, monkeypatch, tmp_path):
        """Integration: real YAML files, both validators, merged result."""
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
        assert result["cluster"]["type"] == "databricks_16_4_med_general_cluster"

    def test_dag_declaration_cache_invalidates_when_content_changes_at_same_mtime(
        self, monkeypatch, tmp_path
    ):
        dag_name = "minimal"
        line = "platform"
        decl_name = f"{dag_name}_declaration.yml"
        cluster_name = f"{dag_name}_cluster.yml"
        fixtures_dir = Path(__file__).resolve().parent / "fixtures"
        dag_dir = tmp_path / line / dag_name
        dag_dir.mkdir(parents=True)
        shutil.copy(fixtures_dir / decl_name, dag_dir / decl_name)
        shutil.copy(fixtures_dir / cluster_name, dag_dir / cluster_name)

        monkeypatch.setattr(
            dag_packages_path_service, "DAG_PACKAGES_ROOT", str(tmp_path)
        )
        DAGPackagesPathService.clear_path_caches()
        try:
            first = DAGYamlParser(dag_name=dag_name).dag_declaration()
            decl_file = dag_dir / decl_name
            original = os.stat(decl_file)
            decl_file.write_text(
                (fixtures_dir / decl_name)
                .read_text()
                .replace("Data Engineering", "Data Platform")
            )
            os.utime(decl_file, ns=(original.st_atime_ns, original.st_mtime_ns))
            assert os.stat(decl_file).st_mtime_ns == original.st_mtime_ns
            second = DAGYamlParser(dag_name=dag_name).dag_declaration()
        finally:
            DAGPackagesPathService.clear_path_caches()

        assert first["dag"]["owner"] == "Data Engineering"
        assert second["dag"]["owner"] == "Data Platform"

    def test_dag_declaration_cache_survives_touch_without_content_change(
        self, monkeypatch, tmp_path
    ):
        dag_name = "minimal"
        line = "platform"
        decl_name = f"{dag_name}_declaration.yml"
        cluster_name = f"{dag_name}_cluster.yml"
        fixtures_dir = Path(__file__).resolve().parent / "fixtures"
        dag_dir = tmp_path / line / dag_name
        dag_dir.mkdir(parents=True)
        shutil.copy(fixtures_dir / decl_name, dag_dir / decl_name)
        shutil.copy(fixtures_dir / cluster_name, dag_dir / cluster_name)

        monkeypatch.setattr(
            dag_packages_path_service, "DAG_PACKAGES_ROOT", str(tmp_path)
        )
        DAGPackagesPathService.clear_path_caches()
        try:
            first = DAGYamlParser(dag_name=dag_name).dag_declaration()
            decl_file = dag_dir / decl_name
            touched = os.stat(decl_file)
            os.utime(
                decl_file,
                ns=(touched.st_atime_ns, touched.st_mtime_ns + 1_000_000_000),
            )
            with mock.patch.object(
                FileService,
                "get_dict_from_yaml_file",
                wraps=FileService.get_dict_from_yaml_file,
            ) as spy:
                second = DAGYamlParser(dag_name=dag_name).dag_declaration()
            assert spy.call_count == 0
            assert second is first
        finally:
            DAGPackagesPathService.clear_path_caches()

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
