from unittest import mock

from hierarchical_conf.hierarchical_conf import HierarchicalConf

from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.services.configuration_service import ConfigurationService


class TestConfigurationService:
    @mock.patch("bietlejuice.services.configuration_service.BIETLEJUICE_PROJECT_ROOT")
    @mock.patch.object(HierarchicalConf, "__init__")
    @mock.patch.object(DAGPackagesPathService, "get_dag_parent_path")
    def test_init_with_dag_name_only(
        self, mock_get_dag_parent_path, mock_super_init, mock_root_constant
    ):
        # arrange
        dag_name = "foo"
        mocked_root = "<bietlejuice_root>"
        mock_root_constant.__str__ = lambda *args: mocked_root
        mock_get_dag_parent_path.return_value = "<dag_root>"

        # act
        ConfigurationService(dag_name)

        # assert
        mock_super_init.assert_called_once_with(
            [
                "<bietlejuice_root>",
                f"<dag_root>/{dag_name}",
                f"<dag_root>/{dag_name}/spark_jobs",
            ]
        )

    @mock.patch("bietlejuice.services.configuration_service.BIETLEJUICE_PROJECT_ROOT")
    @mock.patch.object(HierarchicalConf, "__init__")
    @mock.patch.object(DAGPackagesPathService, "get_dag_parent_path")
    def test_init_with_context(
        self, mock_get_dag_parent_path, mock_super_init, mock_root_constant
    ):
        # arrange
        dag_name = "foo"
        context = "context_name"
        mocked_root = "<bietlejuice_root>"
        mock_root_constant.__str__ = lambda *args: mocked_root
        mock_get_dag_parent_path.return_value = "<dag_root>"

        # act
        ConfigurationService(dag_name, intermediate_path=context)

        # assert
        mock_super_init.assert_called_once_with(
            [
                "<bietlejuice_root>",
                f"<dag_root>/{context}",
                f"<dag_root>/{context}/spark_jobs",
            ]
        )
