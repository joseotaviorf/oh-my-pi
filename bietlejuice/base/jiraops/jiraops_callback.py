import json
from datetime import datetime

from airflow.models import Variable

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.airflow.enums.dag_run_type_enum import DagRunTypeEnum
from bietlejuice.base.jiraops.jiraops_client import JiraOpsClient
from bietlejuice.services.dataset_service import DatasetService

logger = QuintoAndarLogger("JiraOpsCallback")


class JiraOpsCallback:
    """JiraOps Callback class to create alerts on JiraOps"""

    def _create_alert(self, context, alert_type: str, include_task_id: bool = True):
        """
        Create an alert in JiraOps when a task or DAG fails.

        Args:
            context: Airflow context
            alert_type: Type of alert ("task" or "dag")
            include_task_id: If True, include task_id in messages and tags
        """
        task_instance = context.get("task_instance")
        dag_id = task_instance.dag_id
        dag_owner = str(task_instance.task.owner)
        task_id = task_instance.task_id if include_task_id else None
        environment = Variable.get("environment")
        run_type = DatasetService._get_run_type(context)

        logger.info(run_type)
        if environment == "prod" and run_type != DagRunTypeEnum.TEST_RUN:
            log_message = (
                f"DAG [{dag_id}]: Failed task {task_id}, creating alert..."
                if include_task_id
                else f"DAG [{dag_id}]: Failed, creating alert..."
            )
            logger.info(log_message)

            jiraops_credentials = json.loads(Variable.get("JIRA_OPS_ONCALL_APIKEY"))
            current_datetime = datetime.now()
            datetime_str = current_datetime.strftime("%Y-%m-%d %H:%M:%S %z")

            extra_properties = {"DAG": dag_id, "DAGOwner": dag_owner}
            tags = [dag_id, f"{alert_type} failed"]

            if include_task_id:
                message = f"DAG: {dag_id} - Task: {task_id}"
                extra_properties["Task"] = task_id
                tags.insert(1, task_id)
            else:
                message = f"DAG: {dag_id} Failed"

            description = (f"{message} at: {datetime_str}").strip()

            client = JiraOpsClient(jiraops_credentials)
            response = client.create_alert(
                message=message,
                description=description,
                tags=tags,
                extra_properties=extra_properties,
            )

            try:
                response.raise_for_status()
                success_message = (
                    f"Alert created successfully for {dag_id}:{task_id}"
                    if include_task_id
                    else f"Alert created successfully for {dag_id}"
                )
                logger.info(success_message)
            except Exception as e:
                error_message = (
                    f"Failed to create alert for {dag_id}:{task_id}. Status code: {response.status_code}"
                    if include_task_id
                    else f"Failed to create alert for {dag_id}. Status code: {response.status_code}"
                )
                logger.error(error_message)
                logger.error(f"Error message: {e}")
        else:
            logger.info(
                f"""
                    Skipping alert creation, since the environment is not Prod or the run type is TEST_RUN.
                    Run type: {run_type}, Environment: {environment}
                """
            )

    def task_failure_alert(self, context):
        """Create an alert when task fails."""
        self._create_alert(context, alert_type="task", include_task_id=True)

    def dag_failure_alert(self, context):
        """Create an alert when DAG fails."""
        self._create_alert(context, alert_type="dag", include_task_id=False)
