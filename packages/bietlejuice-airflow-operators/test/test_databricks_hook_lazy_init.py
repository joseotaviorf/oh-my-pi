from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch


@patch("databricks_plugin.operators.base_operator.QuintoAndarDatabricksHook")
def test_hook_lazy_init_when_pre_execute_skipped(mock_hook_cls):
    """Hook is created lazily if pre_execute never ran."""
    mock_hook_cls.return_value = MagicMock()
    from databricks_plugin.operators.create_cluster import (
        QuintoAndarDatabricksCreateClusterOperator,
    )

    op = QuintoAndarDatabricksCreateClusterOperator(
        task_id="test", cluster_configuration={}
    )
    assert op._databricks_hook is None
    hook = op.databricks_hook  # triggers lazy init
    mock_hook_cls.assert_called_once_with("databricks_default")
    assert hook is mock_hook_cls.return_value


@patch("databricks_plugin.operators.base_operator.QuintoAndarDatabricksHook")
def test_hook_setter_takes_precedence(mock_hook_cls):
    """Explicit assignment via setter prevents lazy init."""
    from databricks_plugin.operators.create_cluster import (
        QuintoAndarDatabricksCreateClusterOperator,
    )

    op = QuintoAndarDatabricksCreateClusterOperator(
        task_id="test", cluster_configuration={}
    )
    sentinel = MagicMock(name="explicit_hook")
    op.databricks_hook = sentinel
    assert op.databricks_hook is sentinel
    mock_hook_cls.assert_not_called()


@patch("databricks_plugin.operators.base_operator.QuintoAndarDatabricksHook")
def test_check_job_task_execute_pulls_xcom_when_pre_execute_skipped(mock_hook_cls):
    """run_id and job_id are pulled from XCom in execute() if pre_execute was skipped."""
    from databricks_plugin.operators.check_job_task import (
        QuintoAndarDatabricksCheckJobTaskOperator,
    )
    from databricks_plugin.operators.execute_job_cluster import (
        QuintoAndarDatabricksExecuteJobClusterOperator,
    )

    mock_hook_cls.return_value = MagicMock()

    # Build a minimal DAG with execute_job_cluster -> check_job_task
    from airflow import DAG

    dag = DAG("test_dag", start_date=datetime(2026, 1, 1))
    parent = QuintoAndarDatabricksExecuteJobClusterOperator(
        task_id="execute_job_cluster",
        cluster_configuration={},
        dag=dag,
    )
    op = QuintoAndarDatabricksCheckJobTaskOperator(
        task_id="check_task",
        json={},
        dag=dag,
    )
    parent >> op

    # Simulate: pre_execute was SKIPPED, so run_id and job_id are None
    assert op.run_id is None
    assert op.execute_job_cluster_task_id is None

    # Mock context with proper datetime values
    mock_ti = MagicMock()
    mock_ti.start_date = datetime.now(timezone.utc)
    mock_task = MagicMock()
    mock_task.execution_timeout = timedelta(hours=1)
    mock_context = {
        "ti": mock_ti,
        "task": mock_task,
    }
    op.xcom_pull = MagicMock(
        side_effect=lambda ctx, key: {
            "job_id_execute_job_cluster": 123,
            "run_id_execute_job_cluster": 456,
        }.get(key)
    )
    op.xcom_push = MagicMock()

    # Mock the hook methods that execute() calls
    mock_hook = mock_hook_cls.return_value
    mock_state = MagicMock()
    mock_state.is_successful = True
    mock_state.raise_for_state = MagicMock()
    mock_hook.get_job_run_task_state.return_value = mock_state
    mock_hook.get_job_run_task_run_id.return_value = 789
    mock_hook.generate_run_page_url.return_value = "https://example.com"

    # Execute — should pull from XCom and not crash
    op.execute(mock_context)

    # Verify run_id and job_id were pulled from XCom
    assert op.run_id == 456
    assert op.job_id == 123


@patch("databricks_plugin.operators.base_operator.QuintoAndarDatabricksHook")
def test_submit_run_execute_pulls_cluster_id_when_pre_execute_skipped(mock_hook_cls):
    """cluster_id is pulled from XCom in execute() if pre_execute was skipped."""
    from databricks_plugin.operators.submit_run import (
        QuintoAndarDatabricksSubmitRunOperator,
    )

    mock_hook_cls.return_value = MagicMock()
    op = QuintoAndarDatabricksSubmitRunOperator(
        task_id="test",
        json={"spark_python_task": {"python_file": "test.py"}},
    )

    # Simulate: pre_execute was SKIPPED
    assert op.cluster_id is None
    assert op._cluster_resolved is False

    # Mock context
    mock_ti = MagicMock()
    mock_ti.start_date = datetime.now(timezone.utc)
    mock_task = MagicMock()
    mock_task.execution_timeout = timedelta(hours=1)
    mock_context = {
        "ti": mock_ti,
        "task": mock_task,
    }
    op.xcom_pull = MagicMock(
        side_effect=lambda ctx, key: "cluster-abc" if key == "cluster_id" else None
    )
    op.xcom_push = MagicMock()

    # Mock hook methods
    mock_hook = mock_hook_cls.return_value
    mock_state = MagicMock()
    mock_state.is_terminated = False
    mock_state.is_successful = True
    mock_state.raise_for_state = MagicMock()
    mock_hook.get_cluster_state.return_value = mock_state
    mock_hook.submit_run.return_value = 123
    mock_hook.get_job_run.return_value = {"job_id": 1}
    mock_hook.get_job_run_page_url.return_value = "https://example.com"
    mock_hook.get_job_run_state.return_value = mock_state
    mock_hook.get_job_run_logs.return_value = ""

    # Execute — should pull cluster_id from XCom and populate json
    op.execute(mock_context)

    # Verify cluster_id was pulled and json updated
    assert op.json["existing_cluster_id"] == "cluster-abc"
    assert op._cluster_resolved is True


@patch("databricks_plugin.operators.base_operator.QuintoAndarDatabricksHook")
def test_terminate_cluster_execute_pulls_cluster_id_when_pre_execute_skipped(
    mock_hook_cls,
):
    """cluster_id is pulled from XCom in execute() if pre_execute was skipped."""
    from databricks_plugin.operators.terminate_cluster import (
        QuintoAndarDatabricksTerminateClusterOperator,
    )

    mock_hook_cls.return_value = MagicMock()
    op = QuintoAndarDatabricksTerminateClusterOperator(task_id="test")

    # Simulate: pre_execute was SKIPPED
    assert op.cluster_id is None

    # Mock context
    mock_ti = MagicMock()
    mock_ti.start_date = datetime.now(timezone.utc)
    mock_task = MagicMock()
    mock_task.execution_timeout = timedelta(hours=1)
    mock_context = {
        "ti": mock_ti,
        "task": mock_task,
    }
    op.xcom_pull = MagicMock(
        side_effect=lambda ctx, key: "cluster-xyz" if key == "cluster_id" else None
    )

    # Mock hook methods
    mock_hook = mock_hook_cls.return_value
    mock_state = MagicMock()
    mock_state.is_terminated = True
    mock_state.raise_for_state = MagicMock()
    mock_hook.get_cluster_state.return_value = mock_state
    mock_hook.terminate_cluster = MagicMock()

    # Execute — should pull cluster_id from XCom
    op.execute(mock_context)

    # Verify cluster_id was pulled
    assert op.cluster_id == "cluster-xyz"
    mock_hook.terminate_cluster.assert_called_once_with("cluster-xyz")


@patch("databricks_plugin.operators.base_operator.QuintoAndarDatabricksHook")
def test_execute_job_cluster_builds_settings_when_pre_execute_skipped(mock_hook_cls):
    """job_settings are built in execute() if pre_execute was skipped."""
    from airflow import DAG
    from databricks_plugin.operators.execute_job_cluster import (
        QuintoAndarDatabricksExecuteJobClusterOperator,
    )

    mock_hook_cls.return_value = MagicMock()
    dag = DAG("test_dag", start_date=datetime(2026, 1, 1))
    op = QuintoAndarDatabricksExecuteJobClusterOperator(
        task_id="execute_job_cluster",
        cluster_configuration={"spark_version": "16.4"},
        dag=dag,
    )

    # Simulate: pre_execute was SKIPPED
    assert op.job_settings == {}
    assert op._job_settings_built is False

    # Mock context
    mock_ti = MagicMock()
    mock_ti.start_date = datetime.now(timezone.utc)
    mock_task = MagicMock()
    mock_task.execution_timeout = timedelta(hours=1)
    mock_context = {
        "ti": mock_ti,
        "task": mock_task,
        "run_id": "manual_2026-01-01T00:00:00",
    }
    op.xcom_pull = MagicMock(return_value=None)
    op.xcom_push = MagicMock()

    # Mock hook methods
    mock_hook = mock_hook_cls.return_value
    mock_hook.list_jobs.return_value = []
    mock_hook.create_job.return_value = 42
    mock_hook.run_job_now.return_value = 99
    mock_hook.generate_run_page_url.return_value = "https://example.com"
    mock_state = MagicMock()
    mock_state.is_successful = True
    mock_state.raise_for_state = MagicMock()
    mock_hook.get_job_run_state.return_value = mock_state
    mock_hook.get_job_run_cluster_ids.return_value = ["cluster-id-1"]
    cluster_state = MagicMock()
    cluster_state.is_running = True
    cluster_state.raise_for_state = MagicMock()
    mock_hook.get_cluster_state.return_value = cluster_state

    # Execute — should build job_settings
    op.execute(mock_context)

    # Verify job_settings were built
    assert op._job_settings_built is True
    assert "job_clusters" in op.job_settings
    assert "job_cluster_key" in op.job_settings["job_clusters"]
