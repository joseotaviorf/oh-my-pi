from unittest.mock import MagicMock

import pytest

from bietlejuice.base.airflow.task_creators.execute_job_cluster_task_creator import (
    ExecuteJobClusterTaskCreator,
)


class TestGetAccessControlList:
    """Tests for the ACL resolution fallback chain:
    1. cluster_args  ->  2. cluster template  ->  3. default_access_control_list
    """

    _DEFAULT_ACL = [
        {"group_name": "analytics-engineers", "permission_level": "CAN_MANAGE"}
    ]
    _MLOPS_ACL = {"group_name": "mlops", "permission_level": "CAN_MANAGE"}
    _CUSTOM_ACL = {"group_name": "people-analytics", "permission_level": "CAN_MANAGE"}

    @pytest.fixture
    def config_service(self):
        return MagicMock()

    @pytest.fixture
    def dag_execution_context(self):
        ctx = MagicMock()
        ctx.cluster_args = {"type": "some_cluster"}
        return ctx

    def _build_creator(self, dag_execution_context, config_service):
        return ExecuteJobClusterTaskCreator(
            dag_execution_context=dag_execution_context,
            config_service=config_service,
        )

    def test_uses_acl_from_cluster_args_when_present_as_dict(
        self, dag_execution_context, config_service
    ):
        # arrange
        dag_execution_context.cluster_args = {
            "type": "some_cluster",
            "access_control_list": self._CUSTOM_ACL,
        }
        creator = self._build_creator(dag_execution_context, config_service)

        # act
        result = creator._ExecuteJobClusterTaskCreator__get_access_control_list()

        # assert
        assert result == [self._CUSTOM_ACL]
        config_service.get_config.assert_not_called()

    def test_uses_acl_from_cluster_args_when_present_as_list(
        self, dag_execution_context, config_service
    ):
        # arrange
        acl_list = [self._CUSTOM_ACL, self._MLOPS_ACL]
        dag_execution_context.cluster_args = {
            "type": "some_cluster",
            "access_control_list": acl_list,
        }
        creator = self._build_creator(dag_execution_context, config_service)

        # act
        result = creator._ExecuteJobClusterTaskCreator__get_access_control_list()

        # assert
        assert result == acl_list
        config_service.get_config.assert_not_called()

    def test_falls_back_to_cluster_template_acl_when_cluster_args_has_no_acl(
        self, dag_execution_context, config_service
    ):
        # arrange
        dag_execution_context.cluster_args = {"type": "wonka_cluster"}
        config_service.get_config.return_value = {
            "access_control_list": self._MLOPS_ACL
        }
        creator = self._build_creator(dag_execution_context, config_service)

        # act
        result = creator._ExecuteJobClusterTaskCreator__get_access_control_list()

        # assert
        assert result == [self._MLOPS_ACL]
        config_service.get_config.assert_called_once_with("wonka_cluster")

    def test_falls_back_to_cluster_template_acl_list_format(
        self, dag_execution_context, config_service
    ):
        # arrange
        acl_list = [self._MLOPS_ACL, self._CUSTOM_ACL]
        dag_execution_context.cluster_args = {"type": "wonka_cluster"}
        config_service.get_config.return_value = {"access_control_list": acl_list}
        creator = self._build_creator(dag_execution_context, config_service)

        # act
        result = creator._ExecuteJobClusterTaskCreator__get_access_control_list()

        # assert
        assert result == acl_list
        config_service.get_config.assert_called_once_with("wonka_cluster")

    def test_falls_back_to_default_acl_when_template_has_no_acl(
        self, dag_execution_context, config_service
    ):
        # arrange
        dag_execution_context.cluster_args = {
            "type": "databricks_16_4_med_general_cluster"
        }
        config_service.get_config.side_effect = lambda key: {
            "databricks_16_4_med_general_cluster": {},
            "default_access_control_list": self._DEFAULT_ACL,
        }[key]
        creator = self._build_creator(dag_execution_context, config_service)

        # act
        result = creator._ExecuteJobClusterTaskCreator__get_access_control_list()

        # assert
        assert result == [self._DEFAULT_ACL[0]]

    def test_falls_back_to_default_acl_when_cluster_type_is_none(
        self, dag_execution_context, config_service
    ):
        # arrange
        dag_execution_context.cluster_args = {}
        config_service.get_config.return_value = self._DEFAULT_ACL
        creator = self._build_creator(dag_execution_context, config_service)

        # act
        result = creator._ExecuteJobClusterTaskCreator__get_access_control_list()

        # assert
        assert result == [self._DEFAULT_ACL[0]]
        config_service.get_config.assert_called_once_with("default_access_control_list")
