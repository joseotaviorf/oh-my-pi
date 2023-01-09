from unittest.mock import Mock

import mock
import pytest

from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService


class TestDAGPackagesPathService:
    @mock.patch("bietlejuice.base.service.dag_packages_path_service.os.scandir")
    @mock.patch("bietlejuice.base.service.dag_packages_path_service.isdir")
    def test_get_dag_package_path(
        self, mock_isdir, mock_os_scandir, dag_package_service
    ):
        # arrange
        dag_name = "my_dag"
        dir_mock = Mock()
        dir_mock.path = "/path1"
        mock_os_scandir.return_value = [dir_mock]
        mock_isdir.return_value = True
        expected_value = "/path1/my_dag"

        # act
        returned_value = dag_package_service._get_dag_package_path(dag_name)

        # assert
        assert returned_value == expected_value

    @mock.patch("bietlejuice.base.service.dag_packages_path_service.glob")
    def test_get_dag_package_path_for_non_migrated_ones(
        self, mock_glob, dag_package_service
    ):
        # arrange
        dag_name = "my_dag"
        mock_glob.return_value = []
        expected_value = None

        # act
        returned_value = dag_package_service._get_dag_package_path(dag_name)

        # assert
        assert returned_value == expected_value

    @pytest.mark.parametrize(
        "dag_name, is_migrated_mock, expected_return",
        [("dag1", True, "new/path/mocked")],
    )
    @mock.patch.object(DAGPackagesPathService, "_get_dag_package_path")
    def test_get_dag_parent_path(
        self,
        mock_get_dag_package_path,
        dag_name,
        is_migrated_mock,
        expected_return,
        dag_package_service,
    ):
        # arrange
        if is_migrated_mock:
            mock_get_dag_package_path.return_value = f"new/path/mocked/{dag_name}"
        else:
            mock_get_dag_package_path.return_value = False
        # act
        returned_value = dag_package_service.get_dag_parent_path(dag_name)

        # assert
        assert returned_value == expected_return

    @pytest.mark.parametrize(
        "dag_name, dag_path, expected_return",
        [("dag1", "new/path/mocked", "new/path/mocked")],
    )
    @mock.patch.object(DAGPackagesPathService, "_get_dag_package_path")
    def test_get_dag_path(
        self,
        mock_get_dag_package_path,
        dag_name,
        dag_path,
        expected_return,
        dag_package_service,
    ):
        # arrange
        mock_get_dag_package_path.return_value = dag_path

        # act
        returned_value = dag_package_service.get_dag_path(dag_name)

        # assert
        assert returned_value == expected_return
