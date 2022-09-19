from unittest import mock

from hierarchical_conf.hierarchical_conf import HierarchicalConf

from bietlejuice.services.configuration_service import ConfigurationService


class TestConfigurationService:
    @mock.patch("bietlejuice.services.configuration_service.BIETLEJUICE_PROJECT_ROOT")
    @mock.patch.object(HierarchicalConf, "__init__")
    def test_init_with_dag_name_only(self, mock_super_init, mock_root_constant):
        # arrange
        dag_name = "foo"
        mocked_root = "<root>"
        mock_root_constant.__str__ = lambda *args: mocked_root

        # act
        ConfigurationService(dag_name)

        # assert
        mock_super_init.assert_called_once_with(
            searched_paths=[
                mocked_root,
                f"{mocked_root}/dags/{dag_name}",
                f"{mocked_root}/dags/{dag_name}/spark_jobs",
            ]
        )

    @mock.patch("bietlejuice.services.configuration_service.BIETLEJUICE_PROJECT_ROOT")
    @mock.patch.object(HierarchicalConf, "__init__")
    def test_init_with_context(self, mock_super_init, mock_root_constant):
        # arrange
        dag_name = "foo"
        context = "context_name"
        mocked_root = "<root>"
        mock_root_constant.__str__ = lambda *args: mocked_root

        # act
        ConfigurationService(dag_name, intermediate_path=context)

        # assert
        mock_super_init.assert_called_once_with(
            searched_paths=[
                mocked_root,
                f"{mocked_root}/dags/{context}",
                f"{mocked_root}/dags/{context}/spark_jobs",
            ]
        )
