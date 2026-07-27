from typing import Dict, Optional, Tuple

from hierarchical_conf.hierarchical_conf import HierarchicalConf
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.paths import BIETLEJUICE_CONFIG_ROOT
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService

logger = QuintoAndarLogger("ConfigurationService")

# Sentinel dag_name so all Wonka DAGs share one ConfigurationService instance
# and one root conf load (forno_conf / prod_conf only). Real DAG name stays in
# dag_args["name"] for task IDs and logging. Wonka jobs have no folder under
# dags/, so a per-name key would re-parse the shared YAML on every DAG build.
WONKA_SHARED_CONFIG_DAG_NAME = "__wonka__"


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
            object.__setattr__(instance, "_hierarchical_conf_initialized", False)
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

        # Wonka DAGs have no folder in bi-etl-ejuice; share one root-only config.
        if dag_name == WONKA_SHARED_CONFIG_DAG_NAME:
            searched_paths = [f"{BIETLEJUICE_CONFIG_ROOT}"]
        else:
            dag_parent_folder = DAGPackagesPathService.get_dag_parent_path(dag_name)
            if intermediate_path:
                dag_folder = intermediate_path
            else:
                dag_folder = dag_name

            # General configurations file
            searched_paths = [f"{BIETLEJUICE_CONFIG_ROOT}"]

            if dag_folder:
                if dag_parent_folder is not None:
                    # Composer / local: DAG package is on the filesystem
                    searched_paths.append(f"{dag_parent_folder}/{dag_folder}")
                    searched_paths.append(
                        f"{dag_parent_folder}/{dag_folder}/spark_jobs"
                    )
                else:
                    # Databricks: dags/ not on sys.path; read conf from Volume mount
                    _base = HierarchicalConf([BIETLEJUICE_CONFIG_ROOT])
                    volume = _base.get_config("volume_databricks_bucket")
                    dags_prefix = _base.get_config("dags_packages_files_path_in_s3")
                    searched_paths.append(
                        f"{volume}/{dags_prefix}spark_jobs/{dag_folder}"
                    )

        object.__setattr__(self, "_searched_paths", searched_paths)
        object.__setattr__(self, "_config_initialized", True)

    def _ensure_config_loaded(self) -> None:
        """Initialize HierarchicalConf (I/O) on first config access. Idempotent."""
        if self._hierarchical_conf_initialized:
            return
        super().__init__(self._searched_paths)
        object.__setattr__(self, "_hierarchical_conf_initialized", True)

    def __getattribute__(self, name: str):
        if name in ("_configs", "configs"):
            object.__getattribute__(self, "_ensure_config_loaded")()
        return object.__getattribute__(self, name)

    def get_config(self, key: str, *args, **kwargs):
        self._ensure_config_loaded()
        return super().get_config(key, *args, **kwargs)
