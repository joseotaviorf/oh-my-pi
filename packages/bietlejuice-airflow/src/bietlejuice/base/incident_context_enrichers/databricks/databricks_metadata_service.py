import logging
from typing import Optional

from airflow.utils.context import Context
from databricks_plugin.hooks.databricks_hook import QuintoAndarDatabricksHook
from pydantic import BaseModel

from bietlejuice.base.incident_context_enrichers.databricks.databricks_cluster_log_service import (
    DatabricksClusterLogService,
)
from bietlejuice.base.incident_context_enrichers.databricks.databricks_run_error_service import (
    DEFAULT_ERROR_MESSAGE,
    DatabricksRunErrorService,
)

logger = logging.getLogger(__name__)


class DatabricksIncidentContext(BaseModel):
    exception: str = DEFAULT_ERROR_MESSAGE
    log_destination: Optional[str] = None
    databricks_run_url: Optional[str] = None


class DatabricksMetadataService:
    def __init__(
        self,
        dag_id: str,
        databricks_run_url: str,
        databricks_run_id: str,
        databricks_conn_id: str,
    ):
        self.dag_id = dag_id
        self.databricks_run_url = databricks_run_url
        self.databricks_run_id = databricks_run_id

        self.databricks_hook = QuintoAndarDatabricksHook(
            databricks_conn_id=databricks_conn_id
        )

    @classmethod
    def from_airflow_context(
        cls, airflow_context: Context, databricks_conn_id: str
    ) -> Optional["DatabricksMetadataService"]:
        """Factory method to create an instance from an Airflow context.

        Returns None for tasks without a Databricks run.
        """
        dag_id = airflow_context.get("dag_run").dag_id
        task_instance = airflow_context.get("task_instance")
        databricks_run_url = task_instance.xcom_pull(key="run_page_url")
        if not databricks_run_url:
            return None
        databricks_run_id = cls._extract_run_id_from_url(
            url=databricks_run_url, dag_id=dag_id
        )

        return cls(
            dag_id=dag_id,
            databricks_run_url=databricks_run_url,
            databricks_run_id=databricks_run_id,
            databricks_conn_id=databricks_conn_id,
        )

    @classmethod
    def _extract_run_id_from_url(cls, url: str, dag_id: str) -> str:
        """Extracts Databricks run ID from a URL.

        The URL is expected to be in the format:
        https://dbc-xxx.cloud.databricks.com/jobs/<job_id>/runs/<run_id>

        The run ID is the last segment of the URL.
        """
        try:
            url_without_trailing_slash = url.rstrip("/")
            return url_without_trailing_slash.split("/")[-1]
        except Exception:
            logger.error(
                f"DAG {dag_id}: Could not parse Databricks run ID from URL: {url}"
            )
            raise

    def get_databricks_incident_context(self) -> DatabricksIncidentContext:
        """Fetch run error and cluster log location from Databricks.

        Returns:
            DatabricksIncidentContext with the error, log destination, and run URL.
        """
        job_run_metadata = self.databricks_hook.get_job_run(
            run_id=self.databricks_run_id, version="2.2"
        )

        error = DatabricksRunErrorService(
            dag_id=self.dag_id,
            job_run_metadata=job_run_metadata,
            databricks_hook=self.databricks_hook,
        ).get_databricks_run_error()

        log_destination = DatabricksClusterLogService(
            dag_id=self.dag_id,
            job_run_metadata=job_run_metadata,
            databricks_hook=self.databricks_hook,
        ).get_cluster_log_location()

        return DatabricksIncidentContext(
            exception=error,
            log_destination=log_destination,
            databricks_run_url=self.databricks_run_url,
        )
