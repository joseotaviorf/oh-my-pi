from unittest.mock import MagicMock

from airflow.providers.amazon.aws.links.emr import EmrLogsLink
from emr_plugin.links import EMR_LOG_URI_XCOM_KEY, EMR_STEP_LOGS_XCOM_KEY
from emr_plugin.operators.submit_steps import QuintoAndarEmrSubmitStepsOperator


class _FakeTI:
    def __init__(self):
        self.task_id = "t"
        self._xcoms = {}
        self.pushed = {}

    def xcom_pull(self, key, task_ids=None):
        for (task_id, stored_key), value in self._xcoms.items():
            if stored_key == key and (task_ids is None or task_id == task_ids):
                return value
        return None

    def xcom_push(self, key, value):
        self.pushed[key] = value


def test_log_link_reuses_this_tasks_saved_log_uri_without_describe_cluster():
    op = QuintoAndarEmrSubmitStepsOperator(
        task_id="t",
        job_flow_id="j-cluster",
        steps=[{"Name": "n"}],
        wait_for_completion=True,
    )
    hook = MagicMock()
    object.__setattr__(op, "hook", hook)
    op.hook.conn_region_name = "us-east-1"
    op.hook.conn.describe_cluster.return_value = {
        "Cluster": {"LogUri": "s3://own-bucket/logs/jobs/dag/"}
    }

    ti = _FakeTI()
    ti._xcoms[("other", EmrLogsLink.key)] = {"log_uri": "other-bucket/logs/"}
    ti._xcoms[("t", EmrLogsLink.key)] = {"log_uri": "own-bucket/logs/jobs/dag/"}

    op._push_step_logs_link({"ti": ti}, "j-own", ["s-1"])

    assert ti.pushed[EMR_LOG_URI_XCOM_KEY] == "s3://own-bucket/logs/jobs/dag/"
    assert EMR_STEP_LOGS_XCOM_KEY in ti.pushed
    op.hook.conn.describe_cluster.assert_not_called()
