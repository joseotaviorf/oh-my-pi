import os
from typing import Union

import pconf
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.dags import COMPOSER_DAGS_PATH

logger = QuintoAndarLogger("ConfigurationService")


class ConfigurationService:
    """
    Service to retrieve configuration variables from YAML files and enable their access
    according to priority rules based on the scope on which each variable was set, with
    `general` scope as the lowest priority rule and `DAG` or `Spark Job` scopes as the
    highest ones. The environment affects the selection of each variable as well, requiring
    all variables to be replicated in each environment in order to be retrieved and used.
    """

    VALID_ENVIRONMENTS = ["forno", "prod"]

    def __init__(
        self,
        dag_name: str = None,
        inverse_file_config_order: bool = False,
        intermediate_path: str = None,
        env=None,
    ) -> None:
        """
        Constructor.

        :param dag_name: When fetching configuration from a DAG, this is the
         DAG name where the ConfigurationService is going to search for the
         configuration file.
        :param inverse_file_config_order: Since this service gets configs from
         the DAG folder and its spark_jobs folder (besides general configs), it
          can switch where to look for the configs first. Global configs are
          always the last to be read.
          The first to be read has the priority when getting a config by key.
        :param intermediate_path: If there is a nested folder in your dag, add this path here
        :param env: Environment which ConfigurationService should search for configs.
         Must be "prod" or "forno". If not provided, uses the OS env var ENVIRONMENT
        """
        self._dag_name = dag_name
        if env:
            self._validate_environment(env)
            self._env = env
        else:
            self._env = self._get_environment()
        self._config_file_name = f"{self._env}_conf.yml"

        self._general_configuration_file = f"{os.path.dirname(os.path.realpath(__file__))}/../configurations/{self._config_file_name}"

        if intermediate_path:
            self._dag_configuration_file = f"{COMPOSER_DAGS_PATH}/{intermediate_path}/{dag_name}_{self._config_file_name}"
            self._spark_job_configuration_file = f"{COMPOSER_DAGS_PATH}/{intermediate_path}/spark_jobs/{dag_name}_{self._config_file_name}"
        else:
            self._dag_configuration_file = (
                f"{COMPOSER_DAGS_PATH}/{dag_name}/{dag_name}_{self._config_file_name}"
            )
            self._spark_job_configuration_file = f"{COMPOSER_DAGS_PATH}/{dag_name}/spark_jobs/{dag_name}_{self._config_file_name}"

        self._configuration_files = self._get_configuration_files(
            inverse_file_config_order
        )
        self._configs = self._load_configurations_from_files()

    def _get_environment(self) -> str:
        """
        Handles the getting of environment name and the validation.

        :return: the environment name
        """
        env = os.environ.get("ENVIRONMENT")
        self._validate_environment(env)

        return env

    @staticmethod
    def _validate_environment(env: str) -> None:
        """
        Checks whether the environment variable was set in the environment
         where the code is running.

        :raises: ValueError
        """
        if env not in ConfigurationService.VALID_ENVIRONMENTS:
            raise ValueError(
                f"env={env}, valid_envs={ConfigurationService.VALID_ENVIRONMENTS} "
                "msg=The environment variable was not set or is invalid."
            )

    def _get_configuration_files(self, inverse_file_config_order: bool) -> list:
        """
        Identifies the configuration file and add to a list,

        If a DAG name was specified it will try to load the DAG and Spark job
         configuration files.
        The general configuration file is always appended.

        :param inverse_file_config_order: whether it should switch which file
         to load first. If true general configuration files are read first. If
         False the DAGs followed by Spark job files are loaded first.
        The first to be read has the priority when getting a config by key.
        :return: the files ordered by priority
        """
        configuration_files = []

        if self._dag_name:
            if self._config_file_exists(self._dag_configuration_file):
                configuration_files.append(self._dag_configuration_file)

            if self._config_file_exists(self._spark_job_configuration_file):
                configuration_files.append(self._spark_job_configuration_file)

            if inverse_file_config_order:
                configuration_files = configuration_files[::-1]

        configuration_files.append(self._general_configuration_file)
        return configuration_files

    def _config_file_exists(self, config_file_path: str) -> bool:
        """
        Checks if the configuration file path exists.

        :param config_file_path: DAG's or Spark Job's configuration file path
        """
        if not os.path.isfile(config_file_path):
            logger.debug(
                f"dag_name={self._dag_name}, "
                f"ENV={self._env}, "
                f"expected_file={config_file_path}, "
                f"msg=This configuration file was not found in the given path."
            )
            return False
        return True

    def _load_configurations_from_files(self) -> dict:
        """
        Gets the configurations from the yaml files

        :returns: A dictionary with all configs
        """
        pconf.Pconf.clear()

        for file_path in self._configuration_files:
            pconf.Pconf.file(file_path, encoding="yaml")

        return pconf.Pconf.get()

    @property
    def configs(self) -> dict:
        return self._configs.copy()

    def _configuration_key_exists(self, key: str) -> bool:
        """
        Checks if the requested configuration key exists in one of loaded
         configuration files.

        :param key: the configuration key name
        """
        return key in self._configs

    def get_config(self, key: str) -> Union[str, list, dict]:
        """
        Gets configuration value for a specific key

        :returns: The config value
        """
        if not self._configuration_key_exists(key):
            raise IndexError(
                f"configuration_key={key}, env_configuration_file={self._config_file_name}, "
                f"msg=Configuration not registered in configuration file."
            )

        return self.configs[key]
