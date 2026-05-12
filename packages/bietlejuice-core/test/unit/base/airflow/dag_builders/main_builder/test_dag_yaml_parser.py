from unittest import mock

import pytest

from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.services.file_service import FileService


class TestDAGYAMLParser:
    @mock.patch(
        "bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser.DAGDeclarationValidator"
    )
    @mock.patch.object(FileService, "get_dict_from_yaml_file")
    @mock.patch.object(DAGPackagesPathService, "generate_artifact_file_path")
    def test_dag_declaration(
        self,
        mocked_generate_artifact_file_path,
        mocked_get_dict_from_yaml_file,
        mocked_dag_declaration_validator,
        dag_yaml_parser,
    ):
        # arrange
        dag_file_path = "dag/file/path"
        mocked_generate_artifact_file_path.return_value = dag_file_path

        mocked_content = {"a": 1}
        mocked_get_dict_from_yaml_file.return_value = mocked_content

        # act
        returned_value = dag_yaml_parser.dag_declaration()

        # assert
        assert mocked_content == returned_value
        mocked_generate_artifact_file_path.assert_called_once_with(
            artifact_type="dag_declaration", dag_name=""
        )
        mocked_get_dict_from_yaml_file.assert_called_once_with(dag_file_path)
        mocked_dag_declaration_validator.assert_called_once()
        mocked_dag_declaration_validator().validate.assert_called_once_with(
            dag_declaration=mocked_content
        )

    def test_non_existent_dag(self, dag_yaml_parser):
        # arrange
        dag_name = "non_existent_dag"
        dag_yaml_parser._DAGYAMLParser__dag_name = dag_name

        # act & assert
        with pytest.raises(FileNotFoundError):
            dag_yaml_parser.dag_declaration()
