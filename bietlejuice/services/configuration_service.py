from hierarchical_conf.hierarchical_conf import HierarchicalConf
from quintoandar_logger import QuintoAndarLogger

from bietlejuice import BIETLEJUICE_PROJECT_ROOT

logger = QuintoAndarLogger("ConfigurationService")


class ConfigurationService(HierarchicalConf):
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
        dag_folder = dag_name
        if intermediate_path:
            dag_folder = intermediate_path

        general_conf_file = f"{BIETLEJUICE_PROJECT_ROOT}"
        dag_conf_file = f"{BIETLEJUICE_PROJECT_ROOT}/dags/{dag_folder}"
        dag_spark_job_conf_file = (
            f"{BIETLEJUICE_PROJECT_ROOT}/dags/{dag_folder}/spark_jobs"
        )

        super().__init__(
            searched_paths=[general_conf_file, dag_conf_file, dag_spark_job_conf_file]
        )
