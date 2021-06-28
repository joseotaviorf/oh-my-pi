import os
from typing import Union

from pconf import Pconf
from bietlejuice.jobs.composer.dags import COMPOSER_DAGS_PATH
from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("ConfigurationService")


class ConfigurationService:
    """
    Service for getting configuration variables from
    repository, can interact with global variables set
    in the default config location or another yml file.
    """

    ENV = os.environ.get("ENVIRONMENT")
    CONFIG_FILE_NAME = f"{ENV}_conf.yml"
    _general_config_path = f"{os.path.dirname(os.path.realpath(__file__))}/../configurations/{CONFIG_FILE_NAME}"

    def __init__(
        self, source_dag: str = None, inverse_file_config_order: bool = False
    ) -> None:
        """
        :param source_dag: source dag where the ConfigurationService
        is goint to search for configs
        :param inverse_file_config_order: Since this service gets
        configs from the dag folder and the spark_jobs folder (besides
        global configs), it can switch where to look for the configs
        first. Global configs are always the last to be read.
        """

        self._yml_paths = [
            self.get_dag_config_path(source_dag),
            self.get_spark_job_config_path(source_dag),
        ]

        if inverse_file_config_order:
            self._yml_paths = self._yml_paths[::-1]

        self._yml_paths.append(self._general_config_path)

        self._configs = self._load_configs_dict()

    @staticmethod
    def get_dag_config_path(source_dag: str) -> str:
        """
        Gets configuration file path for a specific DAG

        :param source_dag: Name of the DAG
        """
        dag_config_path = f"{COMPOSER_DAGS_PATH}/{source_dag}/{source_dag}_conf.yml"
        return dag_config_path

    @staticmethod
    def get_spark_job_config_path(source_dag: str) -> str:
        """
        Gets configuration file under spark_jobs path for a specific DAG

        :param source_dag: Name of the DAG
        """
        spark_job_config_path = (
            f"{COMPOSER_DAGS_PATH}/{source_dag}/spark_jobs/{source_dag}_conf.yml"
        )
        return spark_job_config_path

    def _load_configs_dict(self) -> dict:
        """
        Gets configurations

        :returns: A dict with all configs
        """
        Pconf.clear()

        for path in self._yml_paths:
            Pconf.file(path, encoding="yaml")

        return Pconf.get()

    @property
    def configs(self):
        return self._configs.copy()

    @logger
    def get_config(self, key: str) -> Union[str, list, dict]:
        """
        Gets configuration for specific key

        :returns: A config value
        """
        configs = self._configs
        return configs[key]
