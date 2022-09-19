from glob import glob
from os.path import dirname

from bietlejuice import BIETLEJUICE_PROJECT_ROOT
from bietlejuice.base.airflow.exceptions.exceptions import DuplicateDAGException
from dags import DAG_PACKAGES_ROOT


class DAGPackagesPathService:
    """
    Abstracts and centralizes path/directory manipulations related to the DAGs or its inner contents.
    """

    @staticmethod
    def get_dag_package_path(dag_name):
        """
        Returns the DAG's path (considering it is inside the DAG Packages structure)

        :param dag_name: the DAG name, that is expected to be unique in the entire platform
        :return: full DAG Package path
        """
        dag_folder = glob(f"{DAG_PACKAGES_ROOT}/**/{dag_name}", recursive=True)

        # Non-migrated DAGs (in bietlejuice module)
        if not dag_folder:
            return None

        if len(dag_folder) > 1:
            raise DuplicateDAGException(
                f"There is more than one registry for the DAG, dag_name={dag_name}"
            )

        return dirname(dag_folder[0])

    @staticmethod
    def get_dag_parent_path(dag_name: str) -> str:
        """
        Gets the DAG's parent path

        Finds the DAG path according to its location: inside the DAG Packages or in the legacy path (bietlejuice)
        :return: full DAG's parent path
        """
        dag_parent_path = DAGPackagesPathService.get_dag_package_path(dag_name)
        if dag_parent_path:
            dag_parent_folder = dag_parent_path
        else:  # TODO: remove after DAG-Packages migration
            dag_parent_folder = f"{BIETLEJUICE_PROJECT_ROOT}/dags"

        return dag_parent_folder
