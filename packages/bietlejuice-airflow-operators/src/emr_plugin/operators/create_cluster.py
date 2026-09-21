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
from copy import copy, deepcopy
from typing import Optional

import requests
from airflow.exceptions import TaskDeferred
from airflow.models import Variable
from airflow.providers.amazon.aws.links.emr import EmrClusterLink
from airflow.providers.amazon.aws.operators.emr import EmrCreateJobFlowOperator

from emr_plugin.capacity_failure import classify_launch_failure, force_x86
from emr_plugin.constants import (
    EMR_CAPACITY_ALERT_WEBHOOK_VARIABLE,
    EMR_DEFAULT_POOL,
    EMR_DEFAULT_POOL_SLOTS,
    EMR_DEFAULT_WAITER_DELAY_SECONDS,
    EMR_DEFAULT_WAITER_MAX_ATTEMPTS,
)
from emr_plugin.links import (
    EMR_CAPACITY_FALLBACK_XCOM_KEY,
    EMR_CLUSTER_LOGS_XCOM_KEY,
    QuintoAndarEmrClusterLogsLink,
    resolve_job_flow_id_from_ti,
)
from emr_plugin.s3_log_links import build_emr_logs_console_url, get_cluster_log_uri
from emr_plugin.template_translator import translate


class QuintoAndarEmrCreateClusterOperator(EmrCreateJobFlowOperator):
    """
    Creates an EMR cluster from a cluster configuration dict that follows the
    same YAML template format used by the Databricks plugin. The configuration
    is translated into EMR ``job_flow_overrides`` before being passed to the
    underlying ``EmrCreateJobFlowOperator``.

    When ``wait_for_completion=True``, the operator waits for provisioning.
    ``deferrable`` defaults to ``False`` so the worker polls synchronously.
    Use ``deferrable=True`` for async triggerer-based waiting.

    Exposes an **EMR Cluster Logs** extra link that opens the correct S3 prefix
    for nested ``LogUri`` layouts.

    :param cluster_configuration: (templated) A dict containing cluster specs
        in the YAML template format (same schema as Databricks configs but with
        EMR values, e.g. ``spark_version: emr-6.15.0``). May include
        ``region_name`` (e.g. ``us-east-1``) to set the AWS region when the
        connection does not specify it; ``region_name`` is not sent to the
        EMR API.
    :type cluster_configuration: dict
    :param aws_conn_id: The Airflow connection used for AWS credentials.
        Defaults to ``aws_default``.
    :type aws_conn_id: str
    :param wait_for_completion: When ``True`` (default), wait until EMR reports the
        cluster ready before task success / XCom (so downstream ``AddJobFlowSteps``
        does not race ``BOOTSTRAPPING``). Use ``False`` only for niche flows that
        intentionally end after ``RunJobFlow`` accepts the request.
    :type wait_for_completion: bool
    :param deferrable: When ``True``, defer while waiting so workers are
        not blocked during provisioning. Defaults to ``False`` (worker polls).
        Ignored when ``wait_for_completion=False``.
    :type deferrable: bool
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

    Additional ``**kwargs`` are passed to ``EmrCreateJobFlowOperator`` (for
    example ``retries`` and ``retry_delay``). EMR job-cluster DAGs built in
    bi-etl-ejuice typically set retries from the DAG declaration (cluster
    ``emr_task_retries`` / ``emr_retry_delay_seconds``).
    """

    template_fields = (
        "cluster_configuration",
    ) + EmrCreateJobFlowOperator.template_fields

    ui_color = "#f9c915"
    ui_fgcolor = "#000"

    operator_extra_links = (EmrClusterLink(), QuintoAndarEmrClusterLogsLink())

    def __init__(
        self,
        cluster_configuration: dict,
        aws_conn_id: str = "aws_default",
        wait_for_completion: bool = True,
        deferrable: bool = False,
        check_interval: int = EMR_DEFAULT_WAITER_DELAY_SECONDS,
        waiter_max_attempts: int = EMR_DEFAULT_WAITER_MAX_ATTEMPTS,
        **kwargs,
    ):
        self.cluster_configuration = cluster_configuration
        cfg = copy(cluster_configuration)
        region_name = cfg.pop("region_name", None)
        job_flow_overrides = translate(cfg)
        if region_name is not None:
            kwargs["region_name"] = region_name
        wait_for_completion_val = kwargs.pop("wait_for_completion", wait_for_completion)
        deferrable_val = kwargs.pop("deferrable", deferrable)
        check_interval_val = kwargs.pop("check_interval", check_interval)
        waiter_max_attempts_val = kwargs.pop("waiter_max_attempts", waiter_max_attempts)
        pool_val = kwargs.pop("pool", EMR_DEFAULT_POOL)
        pool_slots_val = kwargs.pop("pool_slots", EMR_DEFAULT_POOL_SLOTS)
        super().__init__(
            aws_conn_id=aws_conn_id,
            job_flow_overrides=job_flow_overrides,
            wait_for_completion=wait_for_completion_val,
            deferrable=deferrable_val,
            waiter_delay=check_interval_val,
            waiter_max_attempts=waiter_max_attempts_val,
            pool=pool_val,
            pool_slots=pool_slots_val,
            **kwargs,
        )

    @property
    def hook(self):
        if hasattr(self, "_custom_hook") and self._custom_hook is not None:
            return self._custom_hook
        try:
            return super().hook
        except AttributeError:
            return self._emr_hook

    @hook.setter
    def hook(self, value):
        self._custom_hook = value

    @property
    def _emr_hook(self):
        if hasattr(self, "_custom_hook") and self._custom_hook is not None:
            return self._custom_hook
        try:
            return super()._emr_hook
        except AttributeError:
            return self.hook

    @_emr_hook.setter
    def _emr_hook(self, value):
        self._custom_hook = value

    def execute(self, context):
        cfg = deepcopy(self.cluster_configuration)
        _ = cfg.pop("region_name", None)
        ti = context.get("ti")
        if ti:
            fallback_reason = ti.xcom_pull(key=EMR_CAPACITY_FALLBACK_XCOM_KEY)
            if fallback_reason:
                remapped = force_x86(cfg)
                if remapped:
                    pairs = ", ".join(
                        f"{s} -> {t}" for s, t in sorted(remapped.items())
                    )
                    self.log.warning(
                        "EMR capacity/quota fallback active: %s.%s remapped to x86 (%s). Reason: %s",
                        ti.dag_id,
                        ti.task_id,
                        pairs,
                        fallback_reason,
                    )
        self.job_flow_overrides = translate(cfg)
        try:
            job_flow_id = super().execute(context)
        except TaskDeferred:
            self._push_cluster_logs_link(
                context, resolve_job_flow_id_from_ti(context["ti"])
            )
            raise
        except Exception:
            self._handle_launch_failure(context)
            raise
        self._push_cluster_logs_link(context, job_flow_id)
        return job_flow_id

    def execute_complete(self, context, event=None):
        try:
            job_flow_id = super().execute_complete(context, event)
        except Exception:
            self._handle_launch_failure(context, event=event)
            raise
        self._push_cluster_logs_link(context, job_flow_id)
        return job_flow_id

    def _handle_launch_failure(self, context, event=None) -> None:
        ti = context.get("ti")
        if not ti:
            return
        cluster_id = (
            getattr(self, "_job_flow_id", None)
            or (event.get("job_flow_id") if isinstance(event, dict) else None)
            or resolve_job_flow_id_from_ti(ti)
        )
        if not cluster_id:
            return
        try:
            emr_client = self.hook.conn
        except Exception:
            emr_client = None
        reason = classify_launch_failure(emr_client, cluster_id)
        if not reason:
            return

        ti.xcom_push(key=EMR_CAPACITY_FALLBACK_XCOM_KEY, value=reason)
        remapped = force_x86(deepcopy(self.cluster_configuration))
        pairs = (
            ", ".join(f"{s} -> {t}" for s, t in sorted(remapped.items()))
            if remapped
            else "none"
        )
        self.log.warning(
            "EMR capacity/quota failure detected on cluster %s for %s.%s: %s. Flagging x86 retry (%s)",
            cluster_id,
            ti.dag_id,
            ti.task_id,
            reason,
            pairs,
        )
        self._post_capacity_alert(context, reason, remapped)

    def _post_capacity_alert(
        self, context, reason: str, remapped: dict[str, str]
    ) -> None:
        try:
            webhook_url = Variable.get(
                EMR_CAPACITY_ALERT_WEBHOOK_VARIABLE, default_var=None
            )
            if not webhook_url:
                self.log.warning(
                    "EMR capacity alert webhook variable '%s' is not configured; skipping alert.",
                    EMR_CAPACITY_ALERT_WEBHOOK_VARIABLE,
                )
                return

            ti = context["ti"]
            pairs = (
                ", ".join(f"{s} -> {t}" for s, t in sorted(remapped.items()))
                if remapped
                else "none"
            )
            message = (
                f"EMR capacity/quota fallback: {ti.dag_id}.{ti.task_id} retrying on x86 ({pairs}). "
                f"Reason: {reason}"
            )
            response = requests.post(webhook_url, json={"text": message}, timeout=10)
            response.raise_for_status()
        except Exception as exc:
            self.log.warning(
                "Failed to post EMR capacity fallback alert to Google Chat: %s", exc
            )

    def _push_cluster_logs_link(self, context, job_flow_id: Optional[str]) -> None:
        if not job_flow_id:
            return
        fallback_log_uri = (self.job_flow_overrides or {}).get("LogUri")
        log_uri = get_cluster_log_uri(
            self.hook.conn, job_flow_id, fallback_log_uri=fallback_log_uri
        )
        if not log_uri:
            return
        url = build_emr_logs_console_url(
            log_uri=log_uri,
            cluster_id=job_flow_id,
            region_name=self.hook.conn_region_name,
        )
        context["ti"].xcom_push(key=EMR_CLUSTER_LOGS_XCOM_KEY, value=url)
