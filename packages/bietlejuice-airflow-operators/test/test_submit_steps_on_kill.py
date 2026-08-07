from unittest.mock import MagicMock, patch

from emr_plugin.operators.submit_steps import QuintoAndarEmrSubmitStepsOperator


def _make_operator():
    op = QuintoAndarEmrSubmitStepsOperator(
        task_id="t",
        job_flow_id="j-cluster",
        steps=[{"Name": "n"}],
        wait_for_completion=True,
    )
    hook = MagicMock()
    object.__setattr__(op, "hook", hook)
    return op


def test_on_kill_cancels_with_terminate_process():
    op = _make_operator()
    op._submitted_step_ids = ["s-1", "s-2"]
    op._submitted_job_flow_id = "j-abc"
    op.hook.conn.cancel_steps.return_value = {
        "CancelStepsInfoList": [
            {"StepId": "s-1", "Status": "SUBMITTED"},
            {"StepId": "s-2", "Status": "FAILED", "Reason": "NOT_FOUND"},
        ]
    }

    logger = MagicMock()
    with patch.object(QuintoAndarEmrSubmitStepsOperator, "log", logger):
        op.on_kill()

    op.hook.conn.cancel_steps.assert_called_once_with(
        ClusterId="j-abc",
        StepIds=["s-1", "s-2"],
        StepCancellationOption="TERMINATE_PROCESS",
    )
    assert any(
        "Task killed; cancelling EMR steps" in str(call)
        for call in logger.warning.call_args_list
    )


def test_on_kill_logs_rejected_cancel_status():
    op = _make_operator()
    op._submitted_step_ids = ["s-1"]
    op._submitted_job_flow_id = "j-abc"
    op.hook.conn.cancel_steps.return_value = {
        "CancelStepsInfoList": [
            {"StepId": "s-1", "Status": "FAILED", "Reason": "NOT_FOUND"},
        ]
    }
    logger = MagicMock()
    with patch.object(QuintoAndarEmrSubmitStepsOperator, "log", logger):
        op.on_kill()
    assert any(
        "EMR cancel_steps rejected" in str(call) for call in logger.error.call_args_list
    )
    assert any(
        "Task killed; cancelling EMR steps" in str(call)
        for call in logger.warning.call_args_list
    )


def test_execute_captures_step_ids_before_waiter_returns():
    """IDs must be stored from the boto3 submit response, not after the hook waiter."""
    op = _make_operator()
    conn = MagicMock()
    hook = op.hook
    hook.get_conn.return_value = conn
    hook.conn = conn
    waiter_saw_ids = {"value": False}

    def hook_add_job_flow_steps(
        job_flow_id,
        steps=None,
        wait_for_completion=False,
        waiter_delay=None,
        waiter_max_attempts=None,
        execution_role_arn=None,
    ):
        response = conn.add_job_flow_steps(JobFlowId=job_flow_id, Steps=steps or [])
        if wait_for_completion:
            assert op._submitted_step_ids == response["StepIds"]
            waiter_saw_ids["value"] = True
        return response["StepIds"]

    conn.add_job_flow_steps.return_value = {
        "ResponseMetadata": {"HTTPStatusCode": 200},
        "StepIds": ["s-live"],
    }
    hook.add_job_flow_steps.side_effect = hook_add_job_flow_steps

    def fake_parent_execute(self, context):
        return self.hook.add_job_flow_steps(
            job_flow_id=self.job_flow_id,
            steps=self.steps,
            wait_for_completion=True,
        )

    with (
        patch.object(
            QuintoAndarEmrSubmitStepsOperator.__mro__[1],
            "execute",
            fake_parent_execute,
        ),
        patch.object(op, "_persist_step_ids"),
        patch.object(op, "_push_step_logs_link"),
    ):
        result = op.execute(context={"ti": MagicMock()})

    assert result == ["s-live"]
    assert op._submitted_step_ids == ["s-live"]
    assert waiter_saw_ids["value"] is True
    conn.add_job_flow_steps.assert_called_once()
