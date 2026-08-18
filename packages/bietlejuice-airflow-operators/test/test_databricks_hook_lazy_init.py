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
