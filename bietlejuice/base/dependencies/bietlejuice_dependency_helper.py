import re
from typing import Tuple

from bietlejuice.dags import COMPOSER_DAGS_PATH
from bietlejuice.services.file_service import FileService

DEPENDENCIES_PATTERN = "bietlejuice\.(\w*):(.*)"

DAGS_CROSS_DEPENDENCIES_FILE_NAME = "dependencies.yaml"
DAGS_CROSS_DEPENDENCIES_FILE_PATH = (
    f"{COMPOSER_DAGS_PATH}/{DAGS_CROSS_DEPENDENCIES_FILE_NAME}"
)


class BietlejuiceDependencyHelper:
    @staticmethod
    def read_dependencies() -> dict:
        """Reads the dependencies file from the DAGs"""

        return FileService.get_dict_from_yaml_file(DAGS_CROSS_DEPENDENCIES_FILE_PATH)

    @staticmethod
    def extract_dag_and_table_from_task_name(task_name: str) -> Tuple[str, str]:
        """
        Parses the DAG and table name from task name
        """
        if task_name.endswith("-into-redshift"):
            return BietlejuiceDependencyHelper._extract_dag_and_table_from_redshift_task(
                task_name
            )

        if task_name.endswith("-external-table"):
            task_name_pattern = (
                "bietlejuice\.(.*):create-(enrich|raw|clean|dw)*-(.*)-external-table"
            )
        else:
            task_name_pattern = "bietlejuice\.(.*):load-(enrich|raw|clean|dw)*-(.*)"

        match = re.search(task_name_pattern, task_name)
        if match is None:
            match_dag_name = re.search(DEPENDENCIES_PATTERN, task_name)
            dag_name = match_dag_name.group(1)
            return dag_name, None

        dag_name = match.group(1)

        match_layer = re.search("(dw|enrich|clean|raw)", task_name)
        if match_layer is None:
            return dag_name, None

        layer = match_layer.group(1)
        if layer == "dw":
            table_name = BietlejuiceDependencyHelper._get_table_name_from_dw_task(
                dag_name, layer, match.group(3)
            )
        else:
            table_name = match.group(3).replace("-", "_")

        table_name = f"{layer}:{table_name}"
        return dag_name, table_name

    @staticmethod
    def _get_table_name_from_dw_task(dag_name: str, layer: str, task: str) -> str:
        """
        Clean the DW task in order to retrieve the table name being loaded
        """
        dag_context = dag_name.replace(f"{layer}_", "")
        table_name = task.replace("-", "_").replace(f"{dag_context}_", "")
        return table_name

    @staticmethod
    def _extract_dag_and_table_from_redshift_task(task_name: str) -> Tuple[str, str]:
        """
        Parses the DAG and table name from load into redshift tasks
        """
        match = re.search(
            "bietlejuice\.(.*):load-(public)?(.*)-into-redshift", task_name
        )

        if not match:
            match_dag_name = re.search(DEPENDENCIES_PATTERN, task_name)
            dag_name = match_dag_name.group(1)
            return dag_name, None

        layer = "dw"
        dag_name = match.group(1)
        redshift_task = match.group(3)

        table_name = BietlejuiceDependencyHelper._get_table_name_from_dw_task(
            dag_name, layer, redshift_task
        )
        table_name = f"{layer}:{table_name}"

        return dag_name, table_name
