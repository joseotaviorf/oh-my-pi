from mock import patch, call

from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)
from bietlejuice.jobs.composer.dags import COMPOSER_DAGS_PATH


class TestConfigurationService:

    dag_name = "some_awesome_dag"

    def test_get_dag_config_path(self):

        # Arrange
        expected_config_path = (
            f"{COMPOSER_DAGS_PATH}/{self.dag_name}/{self.dag_name}_conf.yml"
        )

        # Act
        config_path = ConfigurationService.get_dag_config_path(self.dag_name)

        # Assert
        assert config_path == expected_config_path

    def test_get_spark_job_config_path(self):

        # Arrange
        expected_config_path = (
            f"{COMPOSER_DAGS_PATH}/{self.dag_name}/spark_jobs/{self.dag_name}_conf.yml"
        )

        # Act
        config_path = ConfigurationService.get_spark_job_config_path(self.dag_name)

        # Assert
        assert config_path == expected_config_path

    @patch("pconf.Pconf.file")
    def test_get_configs_dict_with_additional_ymls(self, mock_file):

        # Act
        cs = ConfigurationService(self.dag_name)

        # Assert
        calls = [
            call(cs.get_dag_config_path(self.dag_name), encoding="yaml"),
            call(cs.get_spark_job_config_path(self.dag_name), encoding="yaml"),
        ]
        mock_file.assert_has_calls(calls)

    @patch("pconf.Pconf.file")
    @patch(
        "bietlejuice.jobs.composer.services.configuration_service.ConfigurationService._general_config_path"
    )
    def test_get_configs_dict_without_additional_param(self, mock_config, mock_file):

        # Act
        ConfigurationService()

        # Assert
        mock_file.assert_called_with(mock_config, encoding="yaml")

    @patch(
        "bietlejuice.jobs.composer.services.configuration_service.ConfigurationService._load_configs_dict"
    )
    def test_get_config(self, mocked_configs):

        # Arrange
        mocked_configs.return_value = {"key": "value"}

        # Act
        cs = ConfigurationService()
        return_value = cs.get_config("key")

        # Assert
        assert return_value == "value"

    @patch("pconf.Pconf.file")
    def test_inverted_file_preference(self, mock_file):

        # Act
        cs = ConfigurationService(self.dag_name, inverse_file_config_order=True)

        # Assert
        calls = [
            call(cs.get_spark_job_config_path(self.dag_name), encoding="yaml"),
            call(cs.get_dag_config_path(self.dag_name), encoding="yaml"),
        ]
        mock_file.assert_has_calls(calls)
