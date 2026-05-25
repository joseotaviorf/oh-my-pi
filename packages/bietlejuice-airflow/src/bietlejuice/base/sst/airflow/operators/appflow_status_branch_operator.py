"""Reusable Airflow BranchPythonOperator for AWS AppFlow status checks.

This operator is the Airflow-side companion of any SST Spark pipeline that
writes an AppFlow status marker file to S3 (the canonical writer is
``bietlejuice.base.sst.pipelines.salesforce.check_appflow_status``, but the
contract is generic). It:

* Reads the JSON marker file produced by the upstream check task using the
  shared layout in :mod:`bietlejuice.base.sst.core.appflow.marker`.
* Returns ``active_task_id`` when the recorded ``flowStatus`` is exactly
  ``Active``, routing the DAG to the normal processing branch.
* Raises ``RuntimeError`` for any other status or when an error is recorded
  in the marker, so the failure is explicit and triggers the DAG's
  ``on_failure_callback``.
* Is prepared for additional routing branches in future sprints: add new
  ``*_task_id`` parameters and extend ``_resolve_branch`` with the new
  conditions.

The operator is independent of any specific source domain: any SST pipeline
that produces a marker compatible with
:func:`bietlejuice.base.sst.core.appflow.marker.build_marker_key` can reuse
it by passing the same ``marker_prefix``, ``bucket`` and partition values.
"""

from airflow.operators.python_operator import BranchPythonOperator
from airflow.utils.decorators import apply_defaults
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.sst.core.appflow.marker import (
    ACTIVE_STATUS,
    DEFAULT_MARKER_PREFIX,
    DEFAULT_REGION,
    build_marker_key,
    read_status_marker,
)

logger = QuintoAndarLogger("sst.airflow.operators.appflow_status_branch")


class AppFlowStatusBranchOperator(BranchPythonOperator):
    """Branch downstream tasks based on an AWS AppFlow status marker.

    Routes to ``active_task_id`` when the AppFlow status is ``Active``.
    Raises :exc:`RuntimeError` for any other status or when the marker
    contains an error, making the failure explicit instead of silently
    skipping the pipeline.

    Parameters
    ----------
    bucket : str
        S3 bucket where the upstream Spark task wrote the marker file. Templated.
    target_table : str
        Logical table identifier; must match the value used when writing the
        marker. Templated.
    partition_date : str
        ``YYYY-MM-DD`` partition that scopes the marker. Templated.
    partition_hour : str
        ``HH`` partition that scopes the marker. Templated.
    active_task_id : str
        ``task_id`` of the downstream task to execute when the flow is Active.
    marker_prefix : str, optional
        Override the S3 key prefix when writers use a non-default location.
        Defaults to
        :data:`bietlejuice.base.sst.core.appflow.marker.DEFAULT_MARKER_PREFIX`.
    region_name : str, optional
        AWS region for the S3 client. Defaults to ``us-east-1``.

    """

    template_fields = tuple(BranchPythonOperator.template_fields) + (
        "bucket",
        "target_table",
        "partition_date",
        "partition_hour",
        "marker_prefix",
    )

    ui_color = "#f4a460"

    @apply_defaults
    def __init__(
        self,
        *,
        bucket: str,
        target_table: str,
        partition_date: str,
        partition_hour: str,
        active_task_id: str,
        marker_prefix: str = DEFAULT_MARKER_PREFIX,
        region_name: str = DEFAULT_REGION,
        **kwargs,
    ) -> None:
        for forbidden in ("python_callable", "op_args", "op_kwargs"):
            kwargs.pop(forbidden, None)
        super().__init__(python_callable=self._resolve_branch, **kwargs)
        self.bucket = bucket
        self.target_table = target_table
        self.partition_date = partition_date
        self.partition_hour = partition_hour
        self.active_task_id = active_task_id
        self.marker_prefix = marker_prefix
        self.region_name = region_name

    def _resolve_branch(self) -> str:
        """BranchPythonOperator callable.

        Returns
        -------
        str
            ``task_id`` of the next task to execute.

        Raises
        ------
        RuntimeError
            When the marker contains an error or the AppFlow status is not
            ``Active``, so the failure is visible and the DAG's
            ``on_failure_callback`` is triggered.
        """
        key = build_marker_key(
            partition_date=self.partition_date,
            partition_hour=self.partition_hour,
            target_table=self.target_table,
            marker_prefix=self.marker_prefix,
        )

        payload = read_status_marker(
            bucket=self.bucket, key=key, region_name=self.region_name
        )

        flow_name = payload.get("flow_name", "<unknown>")
        status = payload.get("status", "")
        error = payload.get("error") or ""

        if error:
            raise RuntimeError(
                f"AppFlow {flow_name!r} reported error: {error!r}. "
                f"Cannot determine next step for {self.target_table!r}."
            )

        if status == ACTIVE_STATUS:
            logger.info(
                f"AppFlow {flow_name!r} is Active. "
                f"Routing to {self.active_task_id!r} for {self.target_table!r}."
            )
            return self.active_task_id

        raise RuntimeError(
            f"AppFlow {flow_name} status={status!r} error={error!r}. "
            f"Cannot process {self.target_table}. "
            f"A handler for non-Active statuses will be added in a future sprint."
        )
        