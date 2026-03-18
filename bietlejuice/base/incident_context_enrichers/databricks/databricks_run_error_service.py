import logging

from databricks_plugin.hooks.databricks_hook import QuintoAndarDatabricksHook

logger = logging.getLogger(__name__)

DEFAULT_ERROR_MESSAGE = (
    "No error available. Please check the Databricks/Airflow run page for more details."
)


class DatabricksRunErrorService:
    """Retrieve Databricks job run errors from the Jobs API."""

    def __init__(
        self,
        dag_id: str,
        job_run_metadata: dict,
        databricks_hook: QuintoAndarDatabricksHook,
    ) -> None:
        self.dag_id = dag_id
        self.job_run_metadata = job_run_metadata
        self.databricks_hook = databricks_hook

    def get_databricks_run_error(self) -> str:
        """Get the error of a Databricks job run.

        Returns:
            Concatenated error string in the format:
            Task '<task_key>': <error>; Task '<task_key>': <error>; ...
        """
        logger.info(
            f"DAG {self.dag_id}: Getting error of run {self.job_run_metadata['run_id']}"
        )
        tasks = self.job_run_metadata.get("tasks")
        errors = [self._get_task_error(task) for task in tasks]

        return "; ".join(errors)

    def _get_task_error(self, task: dict) -> str:
        task_run_id: str = task.get("run_id")
        task_key: str = task.get("task_key")

        run_output = self.databricks_hook.jobs_client.client.get_run_output(
            run_id=task_run_id,
            version="2.2",
        )
        common_errors = run_output.get("error")
        timed_out_errors = (
            run_output.get("metadata", {}).get("state", {}).get("state_message")
        )
        error = common_errors or timed_out_errors

        if not error:
            logger.warning(
                f"DAG {self.dag_id}: No error found for task {task_run_id}. Task key: {task_key}"
            )
            error = DEFAULT_ERROR_MESSAGE

        return f"Task '{task_key}': {error}"
