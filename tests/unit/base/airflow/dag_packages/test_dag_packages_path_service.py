import mock
import pytest

from bietlejuice import BIETLEJUICE_PROJECT_ROOT
from bietlejuice.base.airflow.dag_packages.dag_packages_path_service import (
    DAGPackagesPathService,
)
from bietlejuice.base.airflow.exceptions.exceptions import DuplicateDAGException


class TestDAGPackagesPathService:
    @mock.patch("bietlejuice.base.airflow.dag_packages.dag_packages_path_service.glob")
    def test_get_dag_package_path(self, mock_glob, dag_package_service):
        # arrange
        dag_name = "my_dag"
        mock_glob.return_value = ["/the/dag/path/my_dag"]
        expected_value = "/the/dag/path"

        # act
        returned_value = dag_package_service.get_dag_package_path(dag_name)

        # assert
        assert returned_value == expected_value

    @mock.patch("bietlejuice.base.airflow.dag_packages.dag_packages_path_service.glob")
    def test_get_dag_package_path_for_non_migrated_ones(
        self, mock_glob, dag_package_service
    ):
        # arrange
        dag_name = "my_dag"
        mock_glob.return_value = []
        expected_value = None

        # act
        returned_value = dag_package_service.get_dag_package_path(dag_name)

        # assert
        assert returned_value == expected_value

    @mock.patch("bietlejuice.base.airflow.dag_packages.dag_packages_path_service.glob")
    def test_get_dag_package_path_for_dup_dag(self, mock_glob, dag_package_service):
        # arrange
        dag_name = "my_dag"
        mock_glob.return_value = ["/the/dag/path/my_dag", "/the/dag/otherpath/my_dag"]

        # act & assert
        with pytest.raises(DuplicateDAGException) as e:
            dag_package_service.get_dag_package_path(dag_name)

        assert (
            str(e.value)
            == "There is more than one registry for the DAG, dag_name=my_dag"
        )

    @pytest.mark.parametrize(
        "dag_name, is_migrated_mock, expected_return",
        [
            ("dag1", False, f"{BIETLEJUICE_PROJECT_ROOT}/dags"),
            ("dag2", True, "new/path/mocked"),
        ],
    )
    @mock.patch.object(DAGPackagesPathService, "get_dag_package_path")
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
            mock_get_dag_package_path.return_value = "new/path/mocked"
        else:
            mock_get_dag_package_path.return_value = False
        # act
        returned_value = dag_package_service.get_dag_parent_path(dag_name)

        # assert
        assert returned_value == expected_return
