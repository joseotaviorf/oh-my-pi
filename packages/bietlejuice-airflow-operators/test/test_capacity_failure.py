from __future__ import annotations

from unittest.mock import MagicMock

import botocore.exceptions
import pytest
from emr_plugin.capacity_failure import (
    classify_launch_failure,
    force_x86,
)


def test_quota_error_classifies_as_capacity_failure():
    # Verbatim failure message from 2026-09-10 EMR cluster failures
    message = (
        "The number of vCPUs for instance type r6a.2xlarge exceeds the EC2 service quota "
        "for that type."
    )
    emr_client = MagicMock()
    emr_client.describe_cluster.return_value = {
        "Cluster": {
            "Status": {
                "StateChangeReason": {
                    "Code": "INTERNAL_ERROR",
                    "Message": message,
                }
            }
        }
    }

    result = classify_launch_failure(emr_client, "j-12345")
    assert result == message


def test_insufficient_instance_capacity_classifies_as_capacity_failure():
    message = (
        "InsufficientInstanceCapacity: We currently do not have sufficient capacity."
    )
    emr_client = MagicMock()
    emr_client.describe_cluster.return_value = {
        "Cluster": {
            "Status": {
                "StateChangeReason": {
                    "Code": "INSTANCE_FAILURE",
                    "Message": message,
                }
            }
        }
    }

    result = classify_launch_failure(emr_client, "j-12345")
    assert result == message


@pytest.mark.parametrize(
    "code,message",
    [
        ("STEP_FAILURE", "Shut down as step failed"),
        ("BOOTSTRAP_FAILURE", "Bootstrap action failed"),
        ("INTERNAL_ERROR", "Unrelated internal error with no capacity keywords"),
        ("USER_REQUEST", "Cluster terminated by user"),
    ],
)
def test_non_capacity_failures_return_none(code, message):
    emr_client = MagicMock()
    emr_client.describe_cluster.return_value = {
        "Cluster": {
            "Status": {
                "StateChangeReason": {
                    "Code": code,
                    "Message": message,
                }
            }
        }
    }

    assert classify_launch_failure(emr_client, "j-12345") is None


def test_client_error_from_describe_cluster_returns_none():
    emr_client = MagicMock()
    emr_client.describe_cluster.side_effect = botocore.exceptions.ClientError(
        {"Error": {"Code": "ClusterNotFoundException", "Message": "Cluster not found"}},
        "DescribeCluster",
    )

    assert classify_launch_failure(emr_client, "j-nonexistent") is None


def test_classify_with_missing_client_or_cluster_id():
    assert classify_launch_failure(None, "j-12345") is None
    assert classify_launch_failure(MagicMock(), None) is None


def test_force_x86_maps_scalar_and_node_blocks_and_deduplicates():
    cfg = {
        "master_node_type_id": "r6g.16xlarge",
        "driver_node_type_id": "m6g.xlarge",
        "core_nodes": {
            "node_type_id": "c6g.2xlarge",
            "instance_types": ["r6g.2xlarge", "r7g.2xlarge", "m5.xlarge"],
        },
        "task_nodes": {
            "instance_types": ["m6gd.4xlarge", "m7gd.4xlarge"],
        },
    }

    remapped = force_x86(cfg)

    # Check scalar keys remapped to cheapest x86 equivalent
    assert cfg["master_node_type_id"] == "r6a.16xlarge"
    assert cfg["driver_node_type_id"] == "m6a.xlarge"
    assert cfg["core_nodes"]["node_type_id"] == "c6a.2xlarge"

    # Core nodes: r6g -> r6a, r7g -> r6a (cheapest x86 alternate for both is r6a),
    # deduplicated so r6a.2xlarge appears once; m5.xlarge is unchanged
    assert cfg["core_nodes"]["instance_types"] == ["r6a.2xlarge", "m5.xlarge"]

    # Task nodes: m6gd and m7gd both map to m6id.4xlarge, deduplicated to 1 item
    assert cfg["task_nodes"]["instance_types"] == ["m6id.4xlarge"]

    # Remapped dictionary
    assert remapped["r6g.16xlarge"] == "r6a.16xlarge"
    assert remapped["m6g.xlarge"] == "m6a.xlarge"
    assert remapped["c6g.2xlarge"] == "c6a.2xlarge"
    assert remapped["r6g.2xlarge"] == "r6a.2xlarge"
    assert remapped["r7g.2xlarge"] == "r6a.2xlarge"
    assert remapped["m6gd.4xlarge"] == "m6id.4xlarge"
    assert remapped["m7gd.4xlarge"] == "m6id.4xlarge"
    assert "m5.xlarge" not in remapped


def test_operator_execute_remaps_on_fallback_xcom(monkeypatch):
    from emr_plugin.links import EMR_CAPACITY_FALLBACK_XCOM_KEY
    from emr_plugin.operators.create_cluster import QuintoAndarEmrCreateClusterOperator

    ti = MagicMock()
    ti.dag_id = "test_dag"
    ti.task_id = "test_task"
    ti.xcom_pull.side_effect = lambda key=None: (
        "exceeds quota" if key == EMR_CAPACITY_FALLBACK_XCOM_KEY else None
    )

    context = {"ti": ti}
    cfg = {
        "cluster_name": "test",
        "master_node_type_id": "r6g.xlarge",
        "core_nodes": {
            "instance_types": ["r6g.2xlarge"],
            "target_on_demand": 1,
            "target_spot": 0,
        },
    }
    op = QuintoAndarEmrCreateClusterOperator(
        task_id="test_task", cluster_configuration=cfg
    )

    # Mock super().execute to return job_flow_id without calling boto
    monkeypatch.setattr(
        "airflow.providers.amazon.aws.operators.emr.EmrCreateJobFlowOperator.execute",
        lambda self, ctx: "j-12345",
    )
    monkeypatch.setattr(op, "_push_cluster_logs_link", lambda ctx, jid: None)

    job_flow_id = op.execute(context)
    assert job_flow_id == "j-12345"
    # Overrides should have x86 types leading and expanded with x86 alternates
    fleets = op.job_flow_overrides["Instances"]["InstanceFleets"]
    master_types = [c["InstanceType"] for c in fleets[0]["InstanceTypeConfigs"]]
    core_types = [c["InstanceType"] for c in fleets[1]["InstanceTypeConfigs"]]
    assert master_types == ["r6a.xlarge", "r6i.xlarge", "r7i.xlarge", "r7a.xlarge"]
    assert core_types == ["r6a.2xlarge", "r6i.2xlarge", "r7i.2xlarge", "r7a.2xlarge"]
    assert cfg["master_node_type_id"] == "r6g.xlarge"
    assert cfg["core_nodes"]["instance_types"] == ["r6g.2xlarge"]


def test_operator_execute_handles_capacity_failure_and_alerts(monkeypatch):
    from emr_plugin.links import EMR_CAPACITY_FALLBACK_XCOM_KEY
    from emr_plugin.operators.create_cluster import QuintoAndarEmrCreateClusterOperator

    ti = MagicMock()
    ti.dag_id = "test_dag"
    ti.task_id = "test_task"
    ti.xcom_pull.return_value = None

    context = {"ti": ti}
    cfg = {
        "cluster_name": "test",
        "master_node_type_id": "r6g.xlarge",
    }
    op = QuintoAndarEmrCreateClusterOperator(
        task_id="test_task", cluster_configuration=cfg
    )
    op._job_flow_id = "j-failed"

    mock_emr = MagicMock()
    mock_emr.describe_cluster.return_value = {
        "Cluster": {
            "Status": {
                "StateChangeReason": {
                    "Code": "INTERNAL_ERROR",
                    "Message": "The number of vCPUs for instance type r6a.2xlarge exceeds the EC2 service quota",
                }
            }
        }
    }
    mock_hook = MagicMock()
    mock_hook.conn = mock_emr
    op.hook = mock_hook

    post_mock = MagicMock()
    monkeypatch.setattr("requests.post", post_mock)
    monkeypatch.setattr(
        "airflow.models.Variable.get",
        lambda key, default_var=None: "https://chat.googleapis.com/webhook",
    )

    def raise_err(self, ctx):
        raise RuntimeError("Cluster failed")

    monkeypatch.setattr(
        "airflow.providers.amazon.aws.operators.emr.EmrCreateJobFlowOperator.execute",
        raise_err,
    )

    with pytest.raises(RuntimeError, match="Cluster failed"):
        op.execute(context)

    # Assert XCom pushed
    ti.xcom_push.assert_any_call(
        key=EMR_CAPACITY_FALLBACK_XCOM_KEY,
        value="The number of vCPUs for instance type r6a.2xlarge exceeds the EC2 service quota",
    )
    # Assert post_mock called with text
    assert post_mock.called
    call_args = post_mock.call_args
    assert call_args[0][0] == "https://chat.googleapis.com/webhook"
    payload = call_args[1]["json"]
    assert (
        "EMR capacity/quota fallback: test_dag.test_task retrying on x86"
        in payload["text"]
    )
    assert "r6g.xlarge -> r6a.xlarge" in payload["text"]


def test_operator_hook_properties_compatibility():
    from emr_plugin.operators.create_cluster import QuintoAndarEmrCreateClusterOperator

    cfg = {"cluster_name": "test", "master_node_type_id": "r6g.xlarge"}
    op = QuintoAndarEmrCreateClusterOperator(
        task_id="test_hook", cluster_configuration=cfg
    )

    # Base operator provides either hook or _emr_hook depending on amazon provider version.
    # QuintoAndarEmrCreateClusterOperator must provide both and allow setting both for testing.
    mock_hook_1 = MagicMock()
    mock_hook_1.conn = "mock_conn_1"
    op.hook = mock_hook_1
    assert op.hook == mock_hook_1
    assert op._emr_hook == mock_hook_1

    mock_hook_2 = MagicMock()
    mock_hook_2.conn = "mock_conn_2"
    op._emr_hook = mock_hook_2
    assert op.hook == mock_hook_2
    assert op._emr_hook == mock_hook_2
