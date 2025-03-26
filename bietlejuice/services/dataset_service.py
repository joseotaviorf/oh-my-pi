from airflow.datasets import Dataset
from airflow.utils.context import Context

from bietlejuice.base.dependencies.bietlejuice_dependency_helper import (
    BietlejuiceDependencyHelper,
)


class DatasetService:
    @staticmethod
    def format_dataset_alias(dag_id: str, task_id: str) -> str:
        """Based on Dataset name, format into dataset alias pattern."""
        return f"{dag_id}:{task_id}:alias"

    @staticmethod
    def transform_alias_into_dataset_name(dataset_alias: str) -> str:
        """Transoform Dataset alias into Dataset name."""
        return dataset_alias.replace(":alias")

    @staticmethod
    def get_dag_datasets(dag_id: str) -> list:
        """Reads dependencies file, get all DAG dependencies Datasets and apply logic for reprocessing datasets."""
        dependencies = BietlejuiceDependencyHelper.read_dependencies()
        dag_datasets = None
        dag_datasets_reprocessing = None

        if dag_id not in dependencies:
            return None

        for dependency in dependencies.get(dag_id, []):
            task_dataset = Dataset(dependency)
            task_dataset_reprocessing = Dataset(f"{dependency}:reprocessing")
            dag_datasets = (
                task_dataset if dag_datasets is None else dag_datasets & task_dataset
            )
            dag_datasets_reprocessing = (
                task_dataset_reprocessing
                if dag_datasets_reprocessing is None
                else dag_datasets_reprocessing | task_dataset_reprocessing
            )

        return dag_datasets | dag_datasets_reprocessing

    @staticmethod
    def _is_reprocessing(context: Context) -> bool:
        """Check if the DAG run is a reprocessing or if the event that triggered the DAG was a reprocessing."""
        # Manually marked as reprocessing when the DAG was triggered
        if context.get("params", {}).get("is_reprocessing", False):
            return True
        for triggering_event_name in context.get("triggering_dataset_events", []):
            # If a reprocessing event caused this DAG to trigger, this DAG should also be marked as reprocessing
            if triggering_event_name.endswith(":reprocessing"):
                return True
        return False

    @staticmethod
    def update_datasets(context: Context) -> None:
        if not context.get("params", {}).get("impact_downstream_dependents", True):
            return

        dataset_alias = context["outlets"][0].name
        dataset_name = DatasetService.transform_alias_into_dataset_name(
            dataset_alias=dataset_alias
        )

        if DatasetService._is_reprocessing(context):
            context["outlet_events"][dataset_alias].add(
                Dataset(f"{dataset_name}:reprocessing")
            )
        else:
            context["outlet_events"][dataset_alias].add(Dataset(dataset_name))
