from typing import Dict, Optional, Tuple

from hierarchical_conf.hierarchical_conf import HierarchicalConf
from quintoandar_logger import QuintoAndarLogger

from bietlejuice import BIETLEJUICE_PROJECT_ROOT
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService

logger = QuintoAndarLogger("ConfigurationService")


class ConfigurationService(HierarchicalConf):
    _instance_cache: Dict[
        Tuple[Optional[str], Optional[str]], "ConfigurationService"
    ] = {}

    def __new__(
        cls, dag_name: str = None, intermediate_path: str = None
    ) -> "ConfigurationService":
        key = (dag_name, intermediate_path)
        if key not in cls._instance_cache:
            instance = super().__new__(cls)
            object.__setattr__(instance, "_config_initialized", False)
            cls._instance_cache[key] = instance
        return cls._instance_cache[key]

    def __init__(self, dag_name: str = None, intermediate_path: str = None) -> None:
        """
        Wrapper of Hierarchical Conf

        TODO: the dag_name is not used when intermediate_path is passed.
         We can merge both into one arg.

        It takes the DAG name and intermediate path and build the paths where
         the lib will search the configurations into.

        :param dag_name: the DAG name where the conf file is inside
        :param intermediate_path: optional intermediate path for DAGs inside a context path
        """
        if self._config_initialized:
            return

        dag_parent_folder = DAGPackagesPathService.get_dag_parent_path(dag_name)
        if intermediate_path:
            dag_folder = intermediate_path
        else:
            dag_folder = dag_name

        # General configurations file
        searched_paths = [f"{BIETLEJUICE_PROJECT_ROOT}"]

        if dag_folder:
            # DAG config file
            searched_paths.append(f"{dag_parent_folder}/{dag_folder}")
            # Spark job config file
            searched_paths.append(f"{dag_parent_folder}/{dag_folder}/spark_jobs")

        super().__init__(searched_paths)
        object.__setattr__(self, "_config_initialized", True)
