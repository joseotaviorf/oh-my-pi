from unittest.mock import Mock

import mock
import pytest

from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService


class TestDAGPackagesPathService:
    @mock.patch("bietlejuice.base.service.dag_packages_path_service.scandir")
    @mock.patch("bietlejuice.base.service.dag_packages_path_service.path.isdir")
    def test_find_dag_in_line_folders(
        self, mock_path_isdir, mock_scandir, dag_package_service
    ):
        # arrange
        dag_name = "my_dag"
        dir_mock = Mock()
        dir_mock.path = "/path1"
        mock_scandir.return_value = [dir_mock]
        mock_path_isdir.return_value = True
        expected_value = "/path1/my_dag"

        # act
        returned_value = dag_package_service._find_dag_in_line_folders(dag_name)

        # assert
        assert returned_value == expected_value

    @mock.patch("bietlejuice.base.service.dag_packages_path_service.glob")
    def test_find_dag_in_line_folders_for_non_existent_ones(
        self, mock_glob, dag_package_service
    ):
        # arrange
        dag_name = "my_dag"
        mock_glob.return_value = []
        expected_value = None

        # act
        returned_value = dag_package_service._find_dag_in_line_folders(dag_name)

        # assert
        assert returned_value == expected_value

    @pytest.mark.parametrize(
        "dag_name, is_migrated_mock, expected_return",
        [("dag1", True, "new/path/mocked")],
    )
    @mock.patch.object(DAGPackagesPathService, "_find_dag_in_line_folders")
    def test_get_dag_parent_path(
        self,
        mock_find_dag_in_line_folders,
        dag_name,
        is_migrated_mock,
        expected_return,
        dag_package_service,
    ):
        # arrange
        if is_migrated_mock:
            mock_find_dag_in_line_folders.return_value = f"new/path/mocked/{dag_name}"
        else:
            mock_find_dag_in_line_folders.return_value = False
        # act
        returned_value = dag_package_service.get_dag_parent_path(dag_name)

        # assert
        assert returned_value == expected_return

    @pytest.mark.parametrize(
        "dag_name, dag_path, expected_return",
        [("dag1", "new/path/mocked", "new/path/mocked")],
    )
    @mock.patch.object(DAGPackagesPathService, "_find_dag_in_line_folders")
    def test_get_dag_path(
        self,
        mock_find_dag_in_line_folders,
        dag_name,
        dag_path,
        expected_return,
        dag_package_service,
    ):
        # arrange
        mock_find_dag_in_line_folders.return_value = dag_path

        # act
        returned_value = dag_package_service.get_dag_path(dag_name)

        # assert
        assert returned_value == expected_return
