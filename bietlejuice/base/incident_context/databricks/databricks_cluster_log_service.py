import logging

from databricks_plugin.hooks.databricks_hook import QuintoAndarDatabricksHook

logger = logging.getLogger(__name__)


class DatabricksClusterLogService:
    """Retrieve the S3 log location for a Databricks job run's cluster."""

    def __init__(
        self,
        dag_id: str,
        job_run_metadata: dict,
        databricks_hook: QuintoAndarDatabricksHook,
    ) -> None:
        self.dag_id = dag_id
        self.job_run_metadata = job_run_metadata
        self.databricks_hook = databricks_hook

    def get_cluster_log_location(self) -> str:
        """Get the S3 location of cluster logs for a Databricks job run.

        Returns:
            The full S3 path including the cluster ID, or None if not found.
        """
        logger.info(
            f"DAG {self.dag_id}: Getting cluster log location of run {self.job_run_metadata['run_id']}"
        )

        cluster_id = self.job_run_metadata["tasks"][0]["cluster_instance"]["cluster_id"]

        cluster_info = self.databricks_hook.clusters_client.get_cluster(cluster_id)
        log_destination = cluster_info["cluster_log_conf"]["s3"]["destination"]

        final_log_destination = f"{log_destination}/{cluster_id}"

        logger.info(f"DAG {self.dag_id}: Log destination: {final_log_destination}")
        return final_log_destination
