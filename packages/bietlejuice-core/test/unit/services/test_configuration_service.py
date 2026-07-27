from unittest import mock

from hierarchical_conf.hierarchical_conf import HierarchicalConf

from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.services.configuration_service import (
    WONKA_SHARED_CONFIG_DAG_NAME,
    ConfigurationService,
)


class TestConfigurationService:
    def setup_method(self):
        ConfigurationService._instance_cache.clear()

    def teardown_method(self):
        ConfigurationService._instance_cache.clear()

    @mock.patch("bietlejuice.services.configuration_service.BIETLEJUICE_CONFIG_ROOT")
    @mock.patch.object(HierarchicalConf, "__init__")
    @mock.patch.object(DAGPackagesPathService, "get_dag_parent_path")
    def test_init_with_dag_name_only_defers_hierarchical_conf_load(
        self, mock_get_dag_parent_path, mock_super_init, mock_root_constant
    ):
        # arrange
        dag_name = "foo"
        mocked_root = "<bietlejuice_root>"
        mock_root_constant.__str__ = lambda *args: mocked_root
        mock_get_dag_parent_path.return_value = "<dag_root>"

        # act
        service = ConfigurationService(dag_name)

        # assert — paths computed but HierarchicalConf not loaded yet
        mock_super_init.assert_not_called()
        assert service._searched_paths == [
            "<bietlejuice_root>",
            f"<dag_root>/{dag_name}",
            f"<dag_root>/{dag_name}/spark_jobs",
        ]

    @mock.patch("bietlejuice.services.configuration_service.BIETLEJUICE_CONFIG_ROOT")
    @mock.patch.object(HierarchicalConf, "__init__")
    @mock.patch.object(DAGPackagesPathService, "get_dag_parent_path")
    def test_init_with_context_defers_hierarchical_conf_load(
        self, mock_get_dag_parent_path, mock_super_init, mock_root_constant
    ):
        # arrange
        dag_name = "foo"
        context = "context_name"
        mocked_root = "<bietlejuice_root>"
        mock_root_constant.__str__ = lambda *args: mocked_root
        mock_get_dag_parent_path.return_value = "<dag_root>"

        # act
        service = ConfigurationService(dag_name, intermediate_path=context)

        # assert
        mock_super_init.assert_not_called()
        assert service._searched_paths == [
            "<bietlejuice_root>",
            f"<dag_root>/{context}",
            f"<dag_root>/{context}/spark_jobs",
        ]

    @mock.patch("bietlejuice.services.configuration_service.BIETLEJUICE_CONFIG_ROOT")
    @mock.patch.object(HierarchicalConf, "__init__")
    @mock.patch.object(HierarchicalConf, "get_config")
    @mock.patch.object(DAGPackagesPathService, "get_dag_parent_path")
    def test_get_config_triggers_hierarchical_conf_load(
        self,
        mock_get_dag_parent_path,
        mock_get_config,
        mock_super_init,
        mock_root_constant,
    ):
        mocked_root = "<bietlejuice_root>"
        mock_root_constant.__str__ = lambda *args: mocked_root
        mock_get_dag_parent_path.return_value = "<dag_root>"
        mock_get_config.return_value = "value"

        service = ConfigurationService("my_dag")
        result = service.get_config("some_key")

        mock_super_init.assert_called_once_with(
            [
                "<bietlejuice_root>",
                "<dag_root>/my_dag",
                "<dag_root>/my_dag/spark_jobs",
            ]
        )
        assert result == "value"

    @mock.patch.object(HierarchicalConf, "__init__")
    @mock.patch.object(DAGPackagesPathService, "get_dag_parent_path")
    def test_same_key_returns_same_instance(
        self, mock_get_dag_parent_path, mock_super_init
    ):
        mock_get_dag_parent_path.return_value = "/some/path"

        instance_a = ConfigurationService("my_dag")
        instance_b = ConfigurationService("my_dag")

        assert instance_a is instance_b

    @mock.patch.object(HierarchicalConf, "__init__")
    @mock.patch.object(HierarchicalConf, "get_config")
    @mock.patch.object(DAGPackagesPathService, "get_dag_parent_path")
    def test_hierarchical_conf_init_called_only_once_for_same_key(
        self, mock_get_dag_parent_path, mock_get_config, mock_super_init
    ):
        mock_get_dag_parent_path.return_value = "/some/path"
        mock_get_config.return_value = "value"

        ConfigurationService("my_dag").get_config("key")
        ConfigurationService("my_dag").get_config("key")

        assert mock_super_init.call_count == 1

    @mock.patch.object(HierarchicalConf, "__init__")
    @mock.patch.object(DAGPackagesPathService, "get_dag_parent_path")
    def test_different_keys_create_different_instances(
        self, mock_get_dag_parent_path, mock_super_init
    ):
        mock_get_dag_parent_path.return_value = "/some/path"

        instance_a = ConfigurationService("dag_a")
        instance_b = ConfigurationService("dag_b")

        assert instance_a is not instance_b

    @mock.patch("bietlejuice.services.configuration_service.BIETLEJUICE_CONFIG_ROOT")
    @mock.patch.object(HierarchicalConf, "__init__")
    @mock.patch.object(DAGPackagesPathService, "get_dag_parent_path")
    def test_wonka_shared_config_uses_root_only_paths(
        self, mock_get_dag_parent_path, mock_super_init, mock_root_constant
    ):
        """Wonka sentinel uses only BIETLEJUICE_CONFIG_ROOT; no DAG-specific paths."""
        mocked_root = "<bietlejuice_root>"
        mock_root_constant.__str__ = lambda *args: mocked_root

        svc = ConfigurationService(WONKA_SHARED_CONFIG_DAG_NAME)

        assert svc._searched_paths == [mocked_root]
        mock_super_init.assert_not_called()
        mock_get_dag_parent_path.assert_not_called()

    @mock.patch("bietlejuice.services.configuration_service.BIETLEJUICE_CONFIG_ROOT")
    @mock.patch.object(HierarchicalConf, "__init__")
    def test_wonka_shared_config_same_instance_for_multiple_calls(
        self, mock_super_init, mock_root_constant
    ):
        """All callers of ConfigurationService(__wonka__) get the same instance."""
        mock_root_constant.__str__ = lambda *args: "<root>"

        a = ConfigurationService(WONKA_SHARED_CONFIG_DAG_NAME)
        b = ConfigurationService(WONKA_SHARED_CONFIG_DAG_NAME)

        assert a is b

    @mock.patch("bietlejuice.services.configuration_service.BIETLEJUICE_CONFIG_ROOT")
    @mock.patch.object(HierarchicalConf, "__init__")
    @mock.patch.object(DAGPackagesPathService, "get_dag_parent_path")
    def test_wonka_shared_config_skips_eager_volume_lookup(
        self, mock_get_dag_parent_path, mock_super_init, mock_root_constant
    ):
        """Sentinel must not take the Databricks-volume branch (eager HierarchicalConf)."""
        mocked_root = "<bietlejuice_root>"
        mock_root_constant.__str__ = lambda *args: mocked_root
        mock_get_dag_parent_path.return_value = None

        svc = ConfigurationService(WONKA_SHARED_CONFIG_DAG_NAME)

        assert svc._searched_paths == [mocked_root]
        # Eager volume lookup would have called HierarchicalConf.__init__ during
        # ConfigurationService.__init__; the sentinel skips that entirely.
        mock_super_init.assert_not_called()
        mock_get_dag_parent_path.assert_not_called()
