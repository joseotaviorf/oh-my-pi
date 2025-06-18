from bietlejuice.base.airflow.task_creators.base_task_creator import BaseTaskCreator
from bietlejuice.base.dependencies.bietlejuice_dependency_helper import (
    BietlejuiceDependencyHelper,
)
from bietlejuice.services.dataset_service import DatasetService
from airflow.operators.python import get_current_context, ShortCircuitOperator
from airflow.utils.context import Context


class ReprocessingGuardTaskCreator(BaseTaskCreator):
    """
    Stops a DAG from running multiple times unnecessarily due to reprocessings.
    """

    def create_task(self) -> ShortCircuitOperator:
        return ShortCircuitOperator(
            task_id="reprocessing-guard",
            python_callable=self._should_run_dag,
            dag=self.dag_execution_context.dag,
            doc_md="""\
    Imagine we have a DAG A that triggers B and C, and both B and C are dependencies of D.

    A -> B,C -> D

    When we trigger A passing a ":reprocessing" flag, it will trigger B and C in parallel. When a single one of them finishes, it will
    trigger D (because it is a reprocessing run, not a normal run)
    Then, when the other one finishes, it will trigger D again.

    This task ensures that D will only run once, even if B and C finish at different times. It will identify the origin of the
    reprocessing, and determine which tasks should have finished before the rest of the DAG can continue. If not all dependencies have finished,
    it will save that information in XCOMs and skip the rest of the DAG.
            """,
        )

    def _should_run_dag(self) -> bool:
        context = get_current_context()

        if not DatasetService.is_reprocessing_run(context):
            print("Not a reprocessing run, allowing DAG to continue.")
            return True
        reprocessing_source = DatasetService.find_reprocessing_source(context)
        if reprocessing_source == context["dag"].dag_id:
            print("Reprocessing originated in this DAG. Allowing DAG to continue.")
            return True
        else:
            print(
                f"Reprocessing originated in DAG {reprocessing_source}. Checking dependencies..."
            )

        # If the reprocessing originated from a different DAG, we check if all dependencies that connect to the origin have finished.
        dependencies_that_should_have_finished = self._find_dependencies_that_should_have_finished(
            context, reprocessing_source
        )
        # And we compare that with the dependencies that have actually finished.
        dependencies_that_have_finished = self._find_dependencies_that_have_finished(
            context, reprocessing_source
        )
        if any(
            dep not in dependencies_that_have_finished
            for dep in dependencies_that_should_have_finished
        ):
            print(
                f"Skipping to wait for dependencies to finish: {dependencies_that_should_have_finished - dependencies_that_have_finished}"
            )
            # If any of the dependencies that should have finished have not finished, we skip the rest of the DAG.
            # We also save the dependencies that have finished in XCOMs,
            # so that we can retrieve them in the next run of the DAG.
            self._update_xcoms_with_dependencies(
                context, reprocessing_source, dependencies_that_have_finished
            )
            return False
        else:
            print("All dependencies have finished. Allowing DAG to continue.")
            self._clear_xcoms(context, reprocessing_source)
            return True

    def _find_dependencies_that_should_have_finished(
        self, context: Context, reprocessing_source: str
    ) -> set:
        """
        Returns a set of dependencies that should have finished before the current DAG can continue.

        This is all the :reprocessing dependencies of the current DAG that are connected to the reprocessing source.
        """

        # First, we find all DAGs that the current DAG depends on
        # We'll only consider the dependencies that end with ":reprocessing"
        reprocessing_dependencies_of_current_dag = self._find_reprocessing_dependencies_of_current_dag(
            context
        )
        reprocessing_dag_dependencies_of_current_dag = {
            dataset_name.split(":")[0]  # Extract the DAG name from the dataset name
            for dataset_name in reprocessing_dependencies_of_current_dag
        }

        # Out of those DAGs, we want to find the ones that depend (directly or indirectly) on the reprocessing source.
        dependencies = BietlejuiceDependencyHelper.read_dependencies()
        dags_that_should_have_finished = {
            dag
            for dag in reprocessing_dag_dependencies_of_current_dag
            # If the DAG depends on the reprocessing source, directly or indirectly,
            # it needs to finish before the current DAG can continue. If we don't check this,
            # the current DAG might run multiple times unnecessarily.
            if BietlejuiceDependencyHelper.dag_b_depends_on_dag_a(
                dag_b=dag, dag_a=reprocessing_source, dependencies=dependencies
            )
        }
        dependencies_that_should_have_finished = {
            dependency
            for dependency in reprocessing_dependencies_of_current_dag
            if dependency.split(":")[0] in dags_that_should_have_finished
        }
        return dependencies_that_should_have_finished

    def _find_reprocessing_dependencies_of_current_dag(self, context: Context) -> set:
        dataset_condition = context["dag"].timetable.dataset_condition
        iterator = dataset_condition.iter_datasets()
        reprocessing_dependencies = set()
        for dataset_name, _ in iterator:
            if dataset_name.endswith(":reprocessing"):
                # If the dataset is a reprocessing dataset, we add it to the set
                reprocessing_dependencies.add(dataset_name)
        return reprocessing_dependencies

    def _find_dependencies_that_have_finished(
        self, context: Context, reprocessing_source: str
    ) -> set:
        """
        Checks which dependencies have finished and returns a set of those that have.
        """
        # Some dependencies might have finished previously, and triggered an older run.
        # But that older run skipped the rest of the DAG because it was waiting for another dependency to finish.
        # So we need to check the XCOMs for the finished dependencies from previous runs.
        finished_dependencies_from_previous_run = set(
            context["ti"].xcom_pull(
                key=f"reprocessing_guard_{reprocessing_source}_dependencies",
                task_ids="reprocessing-guard",
                include_prior_dates=True,  # With this flag, Airflow will look for the most recent XCOM from previous runs
            )
            or []
        )

        # We add that to the current run's finished dependencies.
        finished_dependencies_from_current_run = {
            dataset_event_name
            for dataset_event_name in context["triggering_dataset_events"].keys()
            if dataset_event_name.endswith(":reprocessing")
        }
        return finished_dependencies_from_previous_run.union(
            finished_dependencies_from_current_run
        )

    def _update_xcoms_with_dependencies(
        self, context: Context, reprocessing_source: str, dependencies: set
    ) -> None:
        """
        Updates the XCOMs with the dependencies that have finished.
        We will need to retrieve this information in the next run of the DAG.
        """
        context["ti"].xcom_push(
            key=f"reprocessing_guard_{reprocessing_source}_dependencies",
            value=list(dependencies),
        )

    def _clear_xcoms(self, context: Context, reprocessing_source: str) -> None:
        """
        Clears the XCOMs related to the reprocessing source.
        """
        context["ti"].xcom_push(
            key=f"reprocessing_guard_{reprocessing_source}_dependencies", value=None
        )
