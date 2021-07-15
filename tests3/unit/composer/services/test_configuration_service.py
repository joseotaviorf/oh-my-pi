import os

import mock
import pytest
from mock import patch, call

from bietlejuice.jobs.composer.dags import COMPOSER_DAGS_PATH
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)


class TestConfigurationService:
    @mock.patch.object(ConfigurationService, "_load_configurations_from_files")
    @mock.patch.object(ConfigurationService, "_get_configuration_files")
    @mock.patch.object(ConfigurationService, "_get_environment")
    def test__init__(
        self,
        mock__get_environment,
        mock__get_configuration_files,
        mock__load_configurations_from_files,
    ):
        # arrange
        dag_name = "my_awesome_dag"
        inverse_file_config_order = False
        mocked_env = "my_mocked_env"
        mocked_config_files = ["file1", "file2"]
        mocked_configs = {"foo": "bar"}

        mock__get_environment.return_value = mocked_env
        mock__get_configuration_files.return_value = mocked_config_files
        mock__load_configurations_from_files.return_value = mocked_configs

        # act
        configuration_service = ConfigurationService(
            dag_name, inverse_file_config_order
        )

        # assert
        assert configuration_service._env == mocked_env
        assert configuration_service._config_file_name == "my_mocked_env_conf.yml"
        assert configuration_service._configuration_files == mocked_config_files
        assert configuration_service._configs == mocked_configs
        mock__get_environment.assert_called_once_with()
        mock__get_configuration_files.assert_called_once_with(inverse_file_config_order)
        mock__load_configurations_from_files.assert_called_once_with()

    @mock.patch.object(ConfigurationService, "_validate_environment")
    def test__get_environment(
        self, mocked__validate_environment, configuration_service
    ):
        # arrange
        expected_env = "foo"
        os.environ["ENVIRONMENT"] = expected_env

        # act
        returned_env = configuration_service._get_environment()

        # assert
        assert returned_env == expected_env

    def test__validate_environment(self, configuration_service):
        # arrange
        invalid_env = None

        # act & assert
        with pytest.raises(ValueError):
            configuration_service._validate_environment(invalid_env)

    def test__get_configuration_files_without_dag_name(self, configuration_service):
        # arrange
        inverse_file_config_order = False
        configuration_service._dag_name = None

        mocked_general_conf_file_path = "mocked_general_conf_file_path"
        configuration_service._general_configuration_file = (
            mocked_general_conf_file_path
        )

        expected_files = [mocked_general_conf_file_path]

        # act
        returned_files = configuration_service._get_configuration_files(
            inverse_file_config_order
        )

        # assert
        assert returned_files == expected_files

    @mock.patch.object(ConfigurationService, "_config_file_exists")
    def test__get_configuration_files_without_specific_conf_file(
        self, mocked__config_file_exists, configuration_service
    ):
        # arrange
        mocked__config_file_exists.side_effect = [False, False]

        inverse_file_config_order = False
        configuration_service._dag_name = "dag"

        mocked_general_conf_file_path = "mocked_general_conf_file_path"
        configuration_service._general_configuration_file = (
            mocked_general_conf_file_path
        )

        expected_files = [mocked_general_conf_file_path]

        # act
        returned_files = configuration_service._get_configuration_files(
            inverse_file_config_order
        )

        # assert
        assert returned_files == expected_files

    @mock.patch.object(ConfigurationService, "_config_file_exists")
    def test__get_configuration_files_with_dag_conf_file(
        self, mocked__config_file_exists, configuration_service
    ):
        # arrange
        mocked__config_file_exists.side_effect = [True, False]

        inverse_file_config_order = False
        configuration_service._dag_name = "dag"

        mocked_dag_conf_file_path = "mocked_dag_conf_file_path"
        configuration_service._dag_configuration_file = mocked_dag_conf_file_path

        mocked_general_conf_file_path = "mocked_general_conf_file_path"
        configuration_service._general_configuration_file = (
            mocked_general_conf_file_path
        )

        expected_files = [mocked_dag_conf_file_path, mocked_general_conf_file_path]

        # act
        returned_files = configuration_service._get_configuration_files(
            inverse_file_config_order
        )

        # assert
        assert returned_files == expected_files

    @mock.patch.object(ConfigurationService, "_config_file_exists")
    def test__get_configuration_files_with_spark_job_conf_file(
        self, mocked__config_file_exists, configuration_service
    ):
        # arrange
        mocked__config_file_exists.side_effect = [False, True]

        inverse_file_config_order = False
        configuration_service._dag_name = "dag"

        mocked_spark_job_conf_file_path = "mocked_spark_job_conf_file_path"
        configuration_service._spark_job_configuration_file = (
            mocked_spark_job_conf_file_path
        )

        mocked_general_conf_file_path = "mocked_general_conf_file_path"
        configuration_service._general_configuration_file = (
            mocked_general_conf_file_path
        )

        expected_files = [
            mocked_spark_job_conf_file_path,
            mocked_general_conf_file_path,
        ]

        # act
        returned_files = configuration_service._get_configuration_files(
            inverse_file_config_order
        )

        # assert
        assert returned_files == expected_files

    @mock.patch.object(ConfigurationService, "_config_file_exists")
    def test__get_configuration_files_in_inverse_order(
        self, mocked__config_file_exists, configuration_service
    ):
        # arrange
        mocked__config_file_exists.side_effect = [True, True]

        inverse_file_config_order = True
        configuration_service._dag_name = "dag"

        mocked_dag_conf_file_path = "mocked_dag_conf_file_path"
        configuration_service._dag_configuration_file = mocked_dag_conf_file_path

        mocked_spark_job_conf_file_path = "mocked_spark_job_conf_file_path"
        configuration_service._spark_job_configuration_file = (
            mocked_spark_job_conf_file_path
        )

        mocked_general_conf_file_path = "mocked_general_conf_file_path"
        configuration_service._general_configuration_file = (
            mocked_general_conf_file_path
        )

        expected_files = [
            mocked_spark_job_conf_file_path,
            mocked_dag_conf_file_path,
            mocked_general_conf_file_path,
        ]

        # act
        returned_files = configuration_service._get_configuration_files(
            inverse_file_config_order
        )

        # assert
        assert returned_files == expected_files

    @mock.patch(
        "bietlejuice.jobs.composer.services.configuration_service.logger.warning"
    )
    @mock.patch(
        "bietlejuice.jobs.composer.services.configuration_service.os.path.isfile"
    )
    def test_config_file_exists_false(
        self, mocked_isfile, mocked_logger, configuration_service
    ):
        # arrange
        config_file_path = "path"

        dag_name = "dag"
        configuration_service._dag_name = dag_name

        env = "env"
        configuration_service._env = env

        mocked_isfile.return_value = False

        # act
        returned_value = configuration_service._config_file_exists(config_file_path)

        # assert
        assert returned_value is False
        mocked_isfile.assert_called_once_with(config_file_path)
        mocked_logger.assert_called_once_with(
            f"dag_name={dag_name}, "
            f"ENV={env}, "
            f"expected_file={config_file_path}, "
            f"msg=This configuration file was not found in the given path."
        )

    @mock.patch(
        "bietlejuice.jobs.composer.services.configuration_service.os.path.isfile"
    )
    def test_config_file_exists_true(self, mocked_isfile, configuration_service):
        # arrange
        config_file_path = "path"
        mocked_isfile.return_value = True

        # act
        returned_value = configuration_service._config_file_exists(config_file_path)

        # assert
        assert returned_value is True
        mocked_isfile.assert_called_once_with(config_file_path)

    @mock.patch("bietlejuice.jobs.composer.services.configuration_service.pconf")
    def test__load_configurations_from_files(self, mocked_pconf, configuration_service):
        # arrange
        configuration_service._configuration_files = ["a", "b", "c"]

        # act
        configuration_service._load_configurations_from_files()

        # asert
        mocked_pconf.Pconf.clear.assert_called_once_with()
        mocked_pconf.Pconf.file.assert_has_calls(
            [
                call("a", encoding="yaml"),
                call("b", encoding="yaml"),
                call("c", encoding="yaml"),
            ]
        )
        mocked_pconf.Pconf.get.assert_called_once_with()

    def test_configs(self, configuration_service):
        # arrange
        mocked_configs = {"bla": "foo"}
        configuration_service._configs = mocked_configs

        # act
        return_value = configuration_service.configs

        # assert
        assert return_value == mocked_configs

    def test__configuration_key_exists(self, configuration_service):
        # arrange
        key = "cool_key"
        mocked_configs = {"cool_key": "cool_value"}
        configuration_service._configs = mocked_configs

        # act
        returned_value = configuration_service._configuration_key_exists(key)

        # assert
        assert returned_value

    def test__configuration_key_exists_with_invalid_key(self, configuration_service):
        # arrange
        key = "another_key"
        mocked_configs = {"cool_key": "cool_value"}
        configuration_service._configs = mocked_configs

        # act
        returned_value = configuration_service._configuration_key_exists(key)

        # assert
        assert not returned_value

    @mock.patch.object(ConfigurationService, "_configuration_key_exists")
    def test_get_config(self, mocked__configuration_key_exists, configuration_service):
        # arrange
        mocked__configuration_key_exists.return_value = True
        mocked_configs = {"some_key": "some_value"}
        configuration_service._configs = mocked_configs

        # act
        return_value = configuration_service.get_config("some_key")

        # assert
        assert return_value == "some_value"

    @mock.patch.object(ConfigurationService, "_configuration_key_exists")
    def test_get_config_with_invalid_key(
        self, mocked__configuration_key_exists, configuration_service
    ):
        # arrange
        mocked__configuration_key_exists.return_value = False

        # act & assert
        with pytest.raises(IndexError):
            configuration_service.get_config("some_invalid_key")
