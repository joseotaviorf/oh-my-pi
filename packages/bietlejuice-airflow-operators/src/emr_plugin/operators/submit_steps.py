#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#
from typing import Any, Dict, List, Optional

from airflow.exceptions import AirflowException, TaskDeferred
from airflow.providers.amazon.aws.links.emr import EmrClusterLink
from airflow.providers.amazon.aws.operators.emr import EmrAddStepsOperator

from emr_plugin.constants import (
    EMR_DEFAULT_POOL,
    EMR_DEFAULT_POOL_SLOTS,
    EMR_DEFAULT_STEP_WAITER_DELAY_SECONDS,
    EMR_DEFAULT_WAITER_MAX_ATTEMPTS,
)
from emr_plugin.failure_logging import log_emr_step_failures, log_trigger_failure_event
from emr_plugin.links import (
    EMR_LOG_URI_XCOM_KEY,
    EMR_STEP_IDS_XCOM_KEY,
    EMR_STEP_LOGS_XCOM_KEY,
    QuintoAndarEmrStepLogsLink,
)
from emr_plugin.s3_log_links import (
    build_emr_logs_console_url,
    get_cluster_log_uri,
    normalize_log_uri,
)


class QuintoAndarEmrSubmitStepsOperator(EmrAddStepsOperator):
    """
    Submits steps to an existing EMR cluster and optionally waits for their
    completion. Wraps ``EmrAddStepsOperator`` with convenience defaults.

    When ``wait_for_completion=True``, the operator waits on the worker by
    default (``deferrable=False``). Pass ``deferrable=True`` for async
    triggerer-based waiting.

    On step failure, logs ``FailureDetails`` and tails ``stdout.gz`` into the task
    log (with S3 upload wait). Successful steps are not delayed. Exposes an
    **EMR Step Logs** extra link that opens the correct S3 prefix for nested
    ``LogUri`` layouts (e.g. ``s3://bucket/logs/jobs/{dag_id}/``).

    :param job_flow_id: (templated) The EMR cluster ID to add steps to. Can be
        pulled from XCom of a preceding ``QuintoAndarEmrCreateClusterOperator``
        via ``{{ task_instance.xcom_pull(task_ids='create_cluster') }}``.
    :type job_flow_id: str
    :param steps: A list of EMR step dicts. Each step must contain ``Name``,
        ``ActionOnFailure``, and ``HadoopJarStep``. For spark-submit jobs use
        ``command-runner.jar``.
    :type steps: list[dict]
    :param wait_for_completion: Whether to wait until all steps complete.
        Defaults to ``True``.
    :type wait_for_completion: bool
    :param deferrable: When ``True``, defer while waiting so workers are not
        blocked during step execution. Defaults to ``False`` (worker polls).
    :type deferrable: bool
    :param aws_conn_id: The Airflow connection used for AWS credentials.
        Defaults to ``aws_default``.
    :type aws_conn_id: str
    :param check_interval: Seconds between EMR API status checks when waiting
        deferrably (passed as ``waiter_delay`` to the base operator).
        Defaults to 30.
    :type check_interval: int
    :param waiter_max_attempts: Maximum number of boto waiter polls before the
        operator fails. Defaults to ``EMR_DEFAULT_WAITER_MAX_ATTEMPTS`` (10000).
        Set high on purpose so the Airflow task-level ``execution_timeout`` is
        the effective bound; the boto waiter should not fire first. Pass a
        smaller value only if you specifically want the operator to fail
        before the task's ``execution_timeout``.
    :type waiter_max_attempts: int
    :param pool: Airflow pool for this task. Defaults to ``emr_api``.
    :type pool: str
    :param pool_slots: Slots used on ``pool``. Defaults to ``1``.
    :type pool_slots: int

    Additional ``**kwargs`` are passed to ``EmrAddStepsOperator`` (including
    BaseOperator arguments such as ``retries`` and ``retry_delay``). EMR
    job-cluster DAGs built in bi-etl-ejuice typically set these from the DAG
    declaration (cluster ``emr_task_retries`` / ``emr_retry_delay_seconds``).
    """

    ui_color = "#f9c915"
    ui_fgcolor = "#000"

    operator_extra_links = (EmrClusterLink(), QuintoAndarEmrStepLogsLink())

    def __init__(
        self,
        job_flow_id: str,
        steps: list,
        wait_for_completion: bool = True,
        deferrable: bool = False,
        aws_conn_id: str = "aws_default",
        check_interval: int = EMR_DEFAULT_STEP_WAITER_DELAY_SECONDS,
        waiter_max_attempts: int = EMR_DEFAULT_WAITER_MAX_ATTEMPTS,
        **kwargs,
    ):
        wait_for_completion_val = kwargs.pop("wait_for_completion", wait_for_completion)
        check_interval_val = kwargs.pop("check_interval", check_interval)
        deferrable_val = kwargs.pop("deferrable", deferrable)
        waiter_max_attempts_val = kwargs.pop("waiter_max_attempts", waiter_max_attempts)
        pool_val = kwargs.pop("pool", EMR_DEFAULT_POOL)
        pool_slots_val = kwargs.pop("pool_slots", EMR_DEFAULT_POOL_SLOTS)
        super().__init__(
            job_flow_id=job_flow_id,
            steps=steps,
            aws_conn_id=aws_conn_id,
            wait_for_completion=wait_for_completion_val,
            waiter_delay=check_interval_val,
            deferrable=deferrable_val,
            waiter_max_attempts=waiter_max_attempts_val,
            pool=pool_val,
            pool_slots=pool_slots_val,
            **kwargs,
        )
        self._submitted_step_ids: List[str] = []
        self._submitted_job_flow_id: Optional[str] = None

    def execute(self, context):
        # Per-execute reset so in-process re-entry cannot cancel a prior attempt's steps.
        self._submitted_step_ids = []
        self._submitted_job_flow_id = None

        # EmrHook.add_job_flow_steps waits inside the hook when wait_for_completion=True,
        # so wrapping the hook method only captures ids after the step finishes. Capture
        # from the boto3 submit response instead, before the step_complete waiter runs.
        conn = self.hook.get_conn()
        original_get_conn = self.hook.get_conn
        original_conn_add = conn.add_job_flow_steps

        def pinned_get_conn():
            return conn

        def capture_submit(*args, **kwargs):
            response = original_conn_add(*args, **kwargs)
            self._submitted_job_flow_id = kwargs.get("JobFlowId") or (
                args[0] if args else None
            )
            self._submitted_step_ids = list(response.get("StepIds") or [])
            return response

        self.hook.get_conn = pinned_get_conn  # type: ignore[method-assign]
        conn.add_job_flow_steps = capture_submit
        try:
            result = super().execute(context)
            step_ids = self._submitted_step_ids or result
            self._persist_step_ids(context, step_ids)
            self._push_step_logs_link(context, self._submitted_job_flow_id, step_ids)
            return result
        except TaskDeferred:
            self._persist_step_ids(context, self._submitted_step_ids)
            self._push_step_logs_link(
                context, self._submitted_job_flow_id, self._submitted_step_ids
            )
            raise
        except AirflowException:
            self._log_step_failures(
                context, self._submitted_job_flow_id, self._submitted_step_ids
            )
            raise
        finally:
            conn.add_job_flow_steps = original_conn_add
            self.hook.get_conn = original_get_conn  # type: ignore[method-assign]

    def on_kill(self) -> None:
        """Cancel the EMR steps this task submitted so a killed task leaves nothing running."""
        job_flow_id = self._submitted_job_flow_id or self.job_flow_id
        if not job_flow_id or not self._submitted_step_ids:
            self.log.warning(
                "EMR step cancel skipped: no submitted step ids captured for this task instance."
            )
            return
        self.log.warning(
            "Task killed; cancelling EMR steps %s on cluster %s with TERMINATE_PROCESS.",
            self._submitted_step_ids,
            job_flow_id,
        )
        try:
            response = self.hook.conn.cancel_steps(
                ClusterId=job_flow_id,
                StepIds=list(self._submitted_step_ids),
                StepCancellationOption="TERMINATE_PROCESS",
            )
            for info in response.get("CancelStepsInfoList") or []:
                status = info.get("Status")
                step_id = info.get("StepId")
                if status != "SUBMITTED":
                    self.log.error(
                        "EMR cancel_steps rejected for %s: status=%s reason=%s",
                        step_id,
                        status,
                        info.get("Reason"),
                    )
                else:
                    self.log.info("EMR cancel_steps submitted for %s", step_id)
        except Exception as exc:  # noqa: BLE001 - never mask the kill
            self.log.error(
                "EMR cancel_steps failed for %s: %s", self._submitted_step_ids, exc
            )

    def resume_execution(
        self, next_method: str, next_kwargs: Optional[Dict[str, Any]], context
    ):
        """Log EMR step failures when the deferrable trigger fails before resume."""
        if next_method == "__fail__":
            ti = context["ti"]
            job_flow_id = ti.xcom_pull(key="job_flow_id") or self.job_flow_id
            step_ids = self._resolve_step_ids(ti)
            self._log_step_failures(context, job_flow_id, step_ids)
        return super().resume_execution(next_method, next_kwargs, context)

    def execute_complete(self, context, event=None):
        try:
            return super().execute_complete(context, event)
        except AirflowException:
            ti = context["ti"]
            job_flow_id = ti.xcom_pull(key="job_flow_id") or self.job_flow_id
            log_trigger_failure_event(self.log, event)
            step_ids = self._resolve_step_ids(ti)
            self._log_step_failures(context, job_flow_id, step_ids)
            raise

    def _persist_step_ids(self, context, step_ids: Optional[List[str]]) -> None:
        if step_ids:
            context["ti"].xcom_push(key=EMR_STEP_IDS_XCOM_KEY, value=step_ids)

    def _resolve_step_ids(self, ti) -> Optional[List[str]]:
        return ti.xcom_pull(key=EMR_STEP_IDS_XCOM_KEY) or ti.xcom_pull(
            task_ids=ti.task_id
        )

    def _push_step_logs_link(
        self, context, job_flow_id: Optional[str], step_ids: Optional[List[str]]
    ) -> None:
        if not job_flow_id or not step_ids:
            return
        log_uri = get_cluster_log_uri(
            self.hook.conn,
            job_flow_id,
            fallback_log_uri=self._resolve_log_uri(context["ti"]),
        )
        if not log_uri:
            return
        context["ti"].xcom_push(key=EMR_LOG_URI_XCOM_KEY, value=log_uri)
        url = build_emr_logs_console_url(
            log_uri=log_uri,
            cluster_id=job_flow_id,
            step_id=step_ids[0],
            region_name=self.hook.conn_region_name,
        )
        context["ti"].xcom_push(key=EMR_STEP_LOGS_XCOM_KEY, value=url)

    def _resolve_log_uri(self, ti) -> Optional[str]:
        log_uri = ti.xcom_pull(key=EMR_LOG_URI_XCOM_KEY, task_ids=ti.task_id)
        if log_uri:
            return normalize_log_uri(log_uri)
        from airflow.providers.amazon.aws.links.emr import EmrLogsLink

        conf = ti.xcom_pull(key=EmrLogsLink.key, task_ids=ti.task_id)
        if isinstance(conf, dict) and conf.get("log_uri"):
            return normalize_log_uri(conf["log_uri"])
        return None

    def _log_step_failures(
        self, context, job_flow_id: Optional[str], step_ids: Optional[List[str]]
    ) -> None:
        if not job_flow_id or not step_ids:
            return
        if isinstance(step_ids, str):
            step_ids = [step_ids]
        try:
            log_emr_step_failures(
                emr_client=self.hook.conn,
                s3_client=self.hook.get_session().client("s3"),
                cluster_id=job_flow_id,
                step_ids=step_ids,
                logger=self.log,
                log_uri=self._resolve_log_uri(context["ti"]),
            )
        except Exception as exc:  # noqa: BLE001 - never mask the original task failure
            self.log.error("EMR failure log tail skipped: %s", exc)

    @staticmethod
    def build_spark_submit_step(
        name: str,
        script_uri: str,
        args: list = None,
        deploy_mode: str = "client",
        action_on_failure: str = "CONTINUE",
        extra_spark_args: list = None,
    ) -> dict:
        """
        Helper to build a spark-submit step dict.

        :param name: Step name.
        :param script_uri: S3 path to the Python/Jar script.
        :param args: Arguments passed to the script.
        :param deploy_mode: Spark deploy mode (cluster or client).
        :param action_on_failure: EMR action on failure.
        :param extra_spark_args: Additional spark-submit arguments
            (e.g. ``["--jars", "s3://bucket/lib.jar"]``).
        :return: EMR step dict.
        """
        spark_args = [
            "/usr/lib/spark/bin/spark-submit",
            "--master",
            "yarn",
            "--deploy-mode",
            deploy_mode,
        ]
        if extra_spark_args:
            spark_args.extend(extra_spark_args)

        spark_args.append(script_uri)

        if args:
            spark_args.extend(args)

        return {
            "Name": name,
            "ActionOnFailure": action_on_failure,
            "HadoopJarStep": {"Jar": "command-runner.jar", "Args": spark_args},
        }
