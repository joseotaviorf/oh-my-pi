import os
from typing import Union

import pconf
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.dags import COMPOSER_DAGS_PATH

logger = QuintoAndarLogger("ConfigurationService")


class ConfigurationService:
    """
    Service for getting configuration variables from repository, can interact
    with global variables set in the default config location or another yaml
    file.
    """

    VALID_ENVIRONMENTS = ["forno", "prod"]

    def __init__(
        self, dag_name: str = None, inverse_file_config_order: bool = False
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
        """
        self._ENV = self._get_environment()
        self._CONFIG_FILE_NAME = f"{self._ENV}_conf.yml"
        self._GENERAL_CONFIGURATION_FILE = f"{os.path.dirname(os.path.realpath(__file__))}/../configurations/{self._CONFIG_FILE_NAME}"
        self._configuration_files = self._get_configuration_files(
            dag_name, inverse_file_config_order
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

    def _get_configuration_files(
        self, dag_name: str, inverse_file_config_order: bool
    ) -> list:
        """
        Identifies the configuration file and add to a list,

        If a DAG name was specified it will try to load the DAG and Spark job
         configuration files.
        The general configuration file is always appended.

        :param dag_name: the DAG name if the Service is called within a DAG or Spark job
        :param inverse_file_config_order: whether it should switch which file
         to load first. If true general configuration files are read first. If
         False the DAGs followed by Spark job files are loaded first.
        The first to be read has the priority when getting a config by key.
        :return: the files ordered by priority
        """
        configuration_files = []
        dag_config_file = self.get_dag_config_file(dag_name)
        if dag_config_file:
            configuration_files.append(dag_config_file)

        spark_config_file = self.get_spark_job_config_file(dag_name)
        if spark_config_file:
            configuration_files.append(spark_config_file)

        if inverse_file_config_order:
            configuration_files = configuration_files[::-1]

        configuration_files.append(self._GENERAL_CONFIGURATION_FILE)
        return configuration_files

    @staticmethod
    def get_dag_config_file(dag_name: str) -> Union[str, bool]:
        """
        Gets configuration file path for a specific DAG when existent.

        :param dag_name: Name of the DAG
        """
        if dag_name is None:
            return False

        dag_config_file_path = f"{COMPOSER_DAGS_PATH}/{dag_name}/{dag_name}_conf.yml"
        if not os.path.isfile(dag_config_file_path):
            logger.warning(
                f"dag_name={dag_name}, expected_file={dag_config_file_path}, msg=The DAG configuration file does not exist."
            )
            dag_config_file_path = False

        return dag_config_file_path

    @staticmethod
    def get_spark_job_config_file(dag_name: str) -> Union[str, bool]:
        """
        Gets configuration file under spark_jobs path for a specific DAG when
         existent.

        :param dag_name: Name of the DAG
        """
        if dag_name is None:
            return False

        spark_job_config_file_path = (
            f"{COMPOSER_DAGS_PATH}/{dag_name}/spark_jobs/{dag_name}_conf.yml"
        )
        if not os.path.isfile(spark_job_config_file_path):
            spark_job_config_file_path = False

        return spark_job_config_file_path

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
                f"configuration_key={key}, env_configuration_file={self._CONFIG_FILE_NAME}, "
                f"msg=Configuration not registered in configuration file."
            )

        return self.configs[key]
