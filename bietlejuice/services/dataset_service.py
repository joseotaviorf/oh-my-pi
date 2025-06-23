from airflow.datasets import Dataset
from airflow.utils.context import Context
from airflow.utils.types import DagRunType
from airflow.utils.db import create_session
from airflow.models.dataset import DatasetEvent
from sqlalchemy.exc import SQLAlchemyError

from bietlejuice.base.airflow.datasets.dataset_parser import DatasetParser
from bietlejuice.base.dependencies.bietlejuice_dependency_helper import (
    BietlejuiceDependencyHelper,
)
from bietlejuice.base.dependencies.bietlejuice_redundant_dependency_finder import (
    BietlejuiceRedundantDependencyFinder,
)
from typing import Union
from datetime import datetime

from bietlejuice.base.airflow.enums.dag_run_type_enum import DagRunTypeEnum


class DatasetService:
    @staticmethod
    def format_dataset_alias(dag_id: str, task_id: str) -> str:
        """Based on Dataset name, format into dataset alias pattern."""
        return f"{dag_id}:{task_id}:alias"

    @staticmethod
    def transform_alias_into_dataset_name(dataset_alias: str) -> str:
        """Transform Dataset alias into Dataset name."""

        # validation- prefix is temporary
        # Must be removed when we actually migrate to datasets
        return "validation-" + dataset_alias.replace(":alias", "")

    @classmethod
    def get_dag_datasets(cls, dag_id: str) -> Dataset:
        """
        Reads dependencies file, get all DAG dependencies Datasets and apply logic for reprocessing datasets.
        It identifies redundant dependencies automatically.
        """
        dependencies = BietlejuiceDependencyHelper.read_dependencies()
        if dag_id not in dependencies:
            return None
        redundant_dependency_finder = BietlejuiceRedundantDependencyFinder(dependencies)
        redundant_dependencies = redundant_dependency_finder.find_redundant_dependencies(
            dag_id
        )
        return DatasetService.get_dag_datasets_from_dependencies(
            dependencies[dag_id], redundant_dependencies
        )

    @staticmethod
    def get_dag_datasets_from_dependencies(
        dependencies: Union[dict, list], redundant_dependencies: list = None
    ) -> Dataset:
        """
        Given the dependency list, or an object with "any" or "all" keys, assemble the DAG Datasets and apply logic for reprocessing datasets.
        Optionally, you can provide a list of dependencies that were identified as redundant. These will be removed from the "reprocessing"
        section of the dataset logic, to avoid triggering the dependent DAG multiple times.
        """

        if not dependencies:
            return None

        # We're creating all the logic as a dictionary and then parsing the dictionary into a Dataset object
        # That's because we later want to allow custom logic to be defined in the dependencies file
        # So it will be easier to treat everything as a dictionary and then parse it into a Dataset object
        dict_dataset_expression = DatasetService.get_dataset_as_dict_expression_from_dependencies(
            dependencies, redundant_dependencies
        )
        return DatasetParser.parse_dict_expression_as_dataset(dict_dataset_expression)

    @classmethod
    def get_dataset_as_dict_expression_from_dependencies(
        cls, dependencies: Union[dict, list], redundant_dependencies: list = None
    ) -> dict:
        """
        Reads the dependencies (i.e., list of strings in the format <dag_id>:<task_id>,
        or a dict in the formats {"any": []} or {"all": []} with the same format inside the list),
        and returns a dict expression that represents the dataset dependencies.

        For example, the list
        - ["dag1:task1", "dag1:task2", "dag2:task1"]

        Will be transformed into the following dict expression:
        {"any": [
            {"all": ["dag1:task1", "dag1:task2", "dag2:task1"]},
            {"any": [
                "dag1:task1:reprocessing",
                "dag1:task2:reprocessing",
                "dag2:task1:reprocessing"
            ]}
        ]

        And the dict
        {"any": ["dag1:task1", "dag1:task2", "dag2:task1"]}
        Will be transformed into the following dict expression:
        {"any": [
            {"all": ["dag1:task1", "dag1:task2", "dag2:task1"]},
            {"any": [
                "dag1:task1:reprocessing",
                "dag1:task2:reprocessing",
                "dag2:task1:reprocessing"
            ]}
        ]

        Notice that we will trigger the dependent when either:
        1. All dependencies have run since the last execution
        or
        2. Any of the dependencies was reprocessed.

        Optionally, you can provide a list of dependencies that were identified as redundant. These will be removed from the "reprocessing"
        section of the dataset logic, to avoid triggering the dependent DAG multiple times.

        For example, if we have the following dependencies:
        - ["dag1:task1", "dag1:task2", "dag2:task1"]
        And we have the following redundant dependencies:
        - ["dag1:task1"]
        The resulting dict expression will be:
        {"any": [
            {"all": ["dag1:task1", "dag1:task2", "dag2:task1"]},
            {"any": [
                "dag1:task2:reprocessing",
                "dag2:task1:reprocessing"
            ]}
        ]
        }
        """

        if not dependencies:
            return None

        # DAGs are triggered in two circumstances:
        # When all dependencies have run since the last execution
        if isinstance(dependencies, list):
            dag_datasets = {"all": dependencies}
        elif isinstance(dependencies, dict):
            dag_datasets = dependencies
        else:
            raise ValueError(f"Invalid dependencies type: {type(dependencies)}")

        # Or when any of the dependencies was reprocessed (i.e., a dataset with the ":reprocessing" suffix was updated)
        dag_datasets_reprocessing = {"any": []}

        unique_dependencies_without_redundancies = cls._find_unique_dependencies_without_redundancies(
            dependencies, redundant_dependencies
        )
        dag_datasets_reprocessing["any"].extend(
            [
                f"{task}:reprocessing"
                for task in unique_dependencies_without_redundancies
            ]
        )

        return {"any": [dag_datasets, dag_datasets_reprocessing]}

    @classmethod
    def _find_unique_dependencies_without_redundancies(
        cls, dependencies: Union[dict, list], redundant_dependencies: list = None
    ) -> set:
        """
        Given either a list of dependencies or a dict with "any" or "all" keys,
        return a set of unique dependencies.

        Optionally, you can provide a list of dependencies that were identified as redundant. These will be removed.
        """
        unique_dependencies = BietlejuiceDependencyHelper.find_unique_dependencies_in_dependency_object(
            dependencies
        )
        redundant_dependencies = redundant_dependencies or []
        return set(unique_dependencies) - set(redundant_dependencies)

    @classmethod
    def is_reprocessing_run(cls, context: Context) -> bool:
        """Check if the DAG run is a reprocessing or if the event that triggered the DAG was a reprocessing."""
        # Manually marked as reprocessing when the DAG was triggered

        run_type = cls._get_run_type(context)
        if run_type == DagRunTypeEnum.REPROCESSING_RUN:
            return True

        for triggering_event_name in context.get("triggering_dataset_events", {}):
            # If a reprocessing event caused this DAG to trigger, this DAG should also be marked as reprocessing
            if triggering_event_name.endswith(":reprocessing"):
                return True
        return False

    @staticmethod
    def find_reprocessing_source(context: Context) -> str:
        for triggering_event_name, triggering_events in context.get(
            "triggering_dataset_events", {}
        ).items():
            if triggering_event_name.endswith(":reprocessing"):
                # We find the source of the reprocessing event using the extra field
                # If the extra field is not set, we assume the source is the DAG ID
                reprocessing_source = triggering_events[0].extra.get(
                    "reprocessing_source", triggering_events[0].source_dag_id
                )
                if reprocessing_source is None:
                    # May happen if the event was triggered manually
                    # Fallback to the DAG ID from the event name
                    return triggering_event_name.split(":")[0]
                else:
                    return reprocessing_source

        # If it hasn't returned yet, it means the reprocessing was triggered manually
        # The source is the current DAG ID
        return context["dag"].dag_id

    @staticmethod
    def find_reprocessing_date(context: Context) -> str:
        """
        Returns the date of the original reprocessing event that lead to this DAG run.
        We need this because we have a convention that the reprocessing event won't apply
        to future dates.
        """

        for triggering_event_name, triggering_events in context.get(
            "triggering_dataset_events", {}
        ).items():
            if triggering_event_name.endswith(":reprocessing"):
                # We find the date of the reprocessing event using the extra field
                # If the extra field is not set, we assume the date is the current date
                return triggering_events[0].extra.get(
                    "reprocessing_date", datetime.now().date().isoformat()
                )

        # If it hasn't returned yet, it means the reprocessing was triggered manually
        # The date is the current date
        return datetime.now().date().isoformat()

    @classmethod
    def _is_impacting_downstream_dependents(cls, context: Context) -> bool:
        """Check if the DAG run will impact downstream dependendents."""
        # If the param run_type is not defined, we consider that will not impact downstream dependents.
        run_type = cls._get_run_type(context)

        return run_type == DagRunTypeEnum.IMPACT_DOWNSTREAM_DEPENDENTS

    @staticmethod
    def _get_run_type(context: Context) -> DagRunTypeEnum:
        """
        Get the run type of the DAG run based on the context.
        If it is an automatic run (scheduled, dataset or mediator triggered), the default run type is set to
        `IMPACT_DOWNSTREAM_DEPENDENTS`. If it is a manual run, the run type is set to `TEST_RUN` unless it was
        triggered with a specific run type parameter.
        """
        run_type = DagRunTypeEnum(
            context.get("params", {}).get("run_type", DagRunTypeEnum.DEFAULT.value)
        )
        if run_type != DagRunTypeEnum.DEFAULT:
            # If the run type was explicitly set, we use it
            return run_type
        elif context["dag_run"].run_type in (
            DagRunType.SCHEDULED,
            DagRunType.DATASET_TRIGGERED,
        ) or context["dag_run"].run_id.startswith("mediator_trig__"):
            # If it's an automatic run, we set the run type to `IMPACT_DOWNSTREAM_DEPENDENTS`
            return DagRunTypeEnum.IMPACT_DOWNSTREAM_DEPENDENTS
        else:
            return DagRunTypeEnum.TEST_RUN

    @classmethod
    def update_datasets(cls, context: Context) -> None:
        """
        This method is used as a callback to update the datasets after the task has run.

        Here are the rules for updating the datasets:
        - If this is a clear rerun and the dataset was updated before, we do not update it again.
        - If this is a reprocessing run, we update the dataset with a ":reprocessing" suffix.
        - If this is a run that will impact downstream dependents, we update the dataset without a suffix. We
        also update the dataset with a ":first-run-of-day" suffix if this is the first run of the day for this DAG.
        """

        if cls._has_updated_dataset_before(context):
            # If the dataset was updated before, we should not update it again.
            print("Dataset was updated before, skipping update.")
            return

        is_first_run_of_date = cls._is_first_run_of_date(context)

        dataset_alias = context["outlets"][0].name
        dataset_name = DatasetService.transform_alias_into_dataset_name(
            dataset_alias=dataset_alias
        )

        if DatasetService.is_reprocessing_run(context):
            reprocessing_date = DatasetService.find_reprocessing_date(context)
            if reprocessing_date < datetime.now().date().isoformat():
                print(
                    f"Reprocessing date is in the past ({reprocessing_date}), skipping dataset update."
                )
            else:
                print(
                    "This is a reprocessing run, updating the dataset with ':reprocessing' suffix."
                )
                context["outlet_events"][dataset_alias].add(
                    Dataset(f"{dataset_name}:reprocessing"),
                    extra={
                        # The downstream DAGs can use this to know which DAG initially triggered the reprocessing
                        # This is useful to avoid triggering the same DAG multiple times, and for debugging purposes
                        "reprocessing_source": DatasetService.find_reprocessing_source(
                            context
                        ),
                        "reprocessing_date": reprocessing_date,
                    },
                )
        elif DatasetService._is_impacting_downstream_dependents(context):
            print(
                "This run will impact downstream dependents, updating the dataset without a suffix."
            )
            context["outlet_events"][dataset_alias].add(Dataset(dataset_name))
            if is_first_run_of_date:
                # Let's imagine we have a DAG A that is intraday,
                # DAG B depends on DAG A, but DAG B only needs to run once (it is not intraday).
                # It can use the dataset with a suffix of ":first-run-of-day" to trigger the DAG only once.
                print(
                    "This is the first run of the day, updating the dataset with ':first-run-of-day' suffix."
                )
                context["outlet_events"][dataset_alias].add(
                    Dataset(f"{dataset_name}:first-run-of-day")
                )

        cls._update_xcoms(context)

    @staticmethod
    def _has_updated_dataset_before(context: Context) -> bool:
        """
        Check if the current task instance has updated the dataset before.
        If it has, we should not update the dataset again.
        """
        try:
            with create_session() as session:
                dataset_event = (
                    session.query(DatasetEvent)
                    .filter(DatasetEvent.source_task_instance == context["ti"])
                    .first()
                )
        except SQLAlchemyError as e:
            # If, for any reason, we cannot query the database,
            # it's safer to assume that the dataset was not updated before.
            # Otherwise, we might skip updating the dataset incorrectly.
            print(f"Error checking if dataset was updated before: {e}")
            return False

        return dataset_event is not None

    @staticmethod
    def _is_first_run_of_date(context: Context) -> bool:
        """
        Check if the current DAG run is the first run of the day.
        This is used to determine if we should update the dataset with a suffix of ":first-run-of-day".
        """
        last_run_start_date = context["ti"].xcom_pull(
            task_ids=context["task"].task_id,
            key="last_run_start_date",
            include_prior_dates=True,
        )
        return (
            last_run_start_date is None
            or context["ti"].start_date.date() != last_run_start_date.date()
        )

    @staticmethod
    def _update_xcoms(context: Context) -> None:
        """
        Update the XComs with the last run start date.
        This is used to determine if the current DAG run is the first run of the day.
        """
        context["ti"].xcom_push(
            key="last_run_start_date", value=context["ti"].start_date
        )
