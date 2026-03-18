from unittest.mock import MagicMock

from bietlejuice.base.incident_context_enrichers.databricks.databricks_cluster_log_service import (
    DatabricksClusterLogService,
)


def test_returns_log_destination_with_cluster_id():
    hook = MagicMock()
    hook.clusters_client.get_cluster.return_value = {
        "cluster_log_conf": {"s3": {"destination": "s3://databricks-logs/wonka/batch"}}
    }
    metadata = {
        "run_id": "100",
        "tasks": [{"cluster_instance": {"cluster_id": "0611-141754-abc123"}}],
    }

    service = DatabricksClusterLogService(
        dag_id="test_dag",
        job_run_metadata=metadata,
        databricks_hook=hook,
    )

    result = service.get_cluster_log_location()

    assert result == "s3://databricks-logs/wonka/batch/0611-141754-abc123"
    hook.clusters_client.get_cluster.assert_called_once_with("0611-141754-abc123")
