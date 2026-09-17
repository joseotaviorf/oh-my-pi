import json
import sys
import traceback
from datetime import datetime
from typing import List

from airflow.models import Variable
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.airflow.enums.criticality_enum import CriticalityEnum
from bietlejuice.base.airflow.enums.dag_run_type_enum import DagRunTypeEnum
from bietlejuice.base.incident_context_enrichers.enricher import IncidentContextEnricher
from bietlejuice.base.jiraops.jiraops_client import JiraOpsClient
from bietlejuice.services.dataset_service import DatasetService

logger = QuintoAndarLogger("JiraOpsCallback")


class JiraOpsCallback:
    """JiraOps Callback class to create alerts on JiraOps when a task or DAG fails."""

    def __init__(self, dag_args=None, cluster_args=None):
        self.dag_args = dag_args or {}
        self.cluster_args = cluster_args or {}
        self.responder_team_id = self.dag_args.get("jiraops_responder_team_id")
        self._current_dag_id = None
        self._context_enrichers: List[IncidentContextEnricher] = []

    def add_context_enricher(
        self, enricher: IncidentContextEnricher
    ) -> "JiraOpsCallback":
        """Add an enricher to run when building the alert payload. Returns self for chaining."""
        if isinstance(enricher, IncidentContextEnricher):
            self._context_enrichers.append(enricher)
        return self

    def _enrich_alert(self, context, extra_properties: dict, description: str):
        for enricher in self._context_enrichers:
            try:
                extra_properties, description = enricher.enrich(
                    context, extra_properties, description
                )
            except Exception as err:
                exc_type, exc_value, exc_tb = sys.exc_info()
                traceback_str = "".join(
                    traceback.format_exception(exc_type, exc_value, exc_tb)
                )
                logger.warning(
                    f"DAG {self._current_dag_id}: Enricher {type(enricher).__name__} failed. "
                    f"Traceback: {traceback_str} Exception: {err}"
                )
        return extra_properties, description

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
        self._current_dag_id = dag_id
        dag_owner = str(task_instance.task.owner)
        task_id = task_instance.task_id if include_task_id else None
        params = context.get("params") or {}
        criticality = (
            params.get("criticality")
            or self.dag_args.get("criticality")
            or CriticalityEnum.DEFAULT
        )
        table_owner = params.get("owner")
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

            extra_properties = {
                "DAG": dag_id,
                "DAGOwner": dag_owner,
                "Criticality": criticality,
            }
            if table_owner:
                extra_properties["TableOwner"] = table_owner
            tags = [dag_id, f"{alert_type} failed"]

            if include_task_id:
                message = f"DAG: {dag_id} - Task: {task_id}"
                extra_properties["TaskPath"] = f"{dag_id}:{task_id}"
                extra_properties["Task"] = task_id
                tags.insert(1, task_id)
            else:
                message = f"DAG: {dag_id} Failed"

            description = (f"{message} at: {datetime_str}").strip()
            extra_properties, description = self._enrich_alert(
                context, extra_properties, description
            )

            client = JiraOpsClient(jiraops_credentials)
            response = client.create_alert(
                message=message,
                description=description,
                tags=tags,
                extra_properties=extra_properties,
                responder_team_id=self.responder_team_id,
                priority=CriticalityEnum.to_opsgenie_priority(criticality),
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
