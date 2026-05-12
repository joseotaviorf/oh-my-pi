import os
from os.path import dirname
from unittest import mock

from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.services.configuration_service import ConfigurationService


class TestConfigurationService:
    @mock.patch("bietlejuice.services.configuration_service.BIETLEJUICE_CONFIG_ROOT")
    @mock.patch.dict(os.environ, {"ENVIRONMENT": "integration_env"})
    def test_load_confs_global(self, mock_root_constant):
        # arrange
        expected_forno_global_confs = {
            "key1": "value of key1...",
            "key2": "value of key2...",
            "key3": {"foo": "value of key3.foo"},
        }
        mocked_root = f"{dirname(__file__)}/project_root_mock"
        mock_root_constant.__str__ = lambda *args: mocked_root

        # act
        hierarchical_conf = ConfigurationService()

        # assert
        assert hierarchical_conf.configs == expected_forno_global_confs

    @mock.patch("bietlejuice.services.configuration_service.BIETLEJUICE_CONFIG_ROOT")
    @mock.patch.object(DAGPackagesPathService, "get_dag_parent_path")
    @mock.patch.dict(os.environ, {"ENVIRONMENT": "integration_env"})
    def test_load_confs_for_some_dag(
        self, mock_get_dag_parent_path, mock_root_constant
    ):
        """Testing a DAG with dag confs only"""
        # arrange
        dag_name = "foo"
        expected_confs = {
            "key1": "value of key1...",
            "key2": "Value from DAG conf",
            "key3": {"foo": "new value form DAG conf"},
        }

        mocked_root = f"{dirname(__file__)}/project_root_mock"
        mock_root_constant.__str__ = lambda *args: mocked_root
        mock_get_dag_parent_path.return_value = f"{mocked_root}/dags"

        # act
        hierarchical_conf = ConfigurationService(dag_name=dag_name)

        # assert
        assert hierarchical_conf.configs == expected_confs

    @mock.patch("bietlejuice.services.configuration_service.BIETLEJUICE_CONFIG_ROOT")
    @mock.patch.object(DAGPackagesPathService, "get_dag_parent_path")
    @mock.patch.dict(os.environ, {"ENVIRONMENT": "integration_env"})
    def test_load_confs_for_some_dag_spark_jobs(
        self, mock_get_dag_parent_path, mock_root_constant
    ):
        """Testing a DAG with DAG confs and spark jobs confs"""
        # arrange
        dag_name = "bar"
        expected_confs = {
            "key1": "value of key1...",
            "key2": "Value from bar DAG conf",
            "key3": {"foo": "value from bar spark job conf"},
            "key4": 220995,
        }

        mocked_root = f"{dirname(__file__)}/project_root_mock"
        mock_root_constant.__str__ = lambda *args: mocked_root
        mock_get_dag_parent_path.return_value = f"{mocked_root}/dags"

        # act
        hierarchical_conf = ConfigurationService(dag_name=dag_name)

        # assert
        assert hierarchical_conf.configs == expected_confs
