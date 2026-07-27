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
from airflow.providers.amazon.aws.operators.emr import EmrTerminateJobFlowOperator

from emr_plugin.constants import (
    EMR_DEFAULT_POOL,
    EMR_DEFAULT_POOL_SLOTS,
    EMR_DEFAULT_WAITER_DELAY_SECONDS,
)


class QuintoAndarEmrTerminateClusterOperator(EmrTerminateJobFlowOperator):
    """
    Terminates an EMR cluster. Wraps ``EmrTerminateJobFlowOperator`` with
    convenience defaults.

    :param job_flow_id: (templated) The EMR cluster ID to terminate. Can be
        pulled from XCom of a preceding ``QuintoAndarEmrCreateClusterOperator``
        via ``{{ task_instance.xcom_pull(task_ids='create_cluster') }}``.
    :type job_flow_id: str
    :param aws_conn_id: The Airflow connection used for AWS credentials.
        Defaults to ``aws_default``.
    :type aws_conn_id: str
    :param deferrable: When ``True``, defer while waiting so workers are not
        blocked during termination. Defaults to ``False`` (worker polls).
    :type deferrable: bool
    :param check_interval: Seconds between EMR API status checks when waiting
        deferrably (passed as ``waiter_delay`` to the base operator).
        Defaults to 30.
    :type check_interval: int
    :param pool: Airflow pool for this task. Defaults to ``emr_api``.
    :type pool: str
    :param pool_slots: Slots used on ``pool``. Defaults to ``1``.
    :type pool_slots: int

    Additional ``**kwargs`` are passed to ``EmrTerminateJobFlowOperator``
    (including ``retries`` and ``retry_delay``). EMR job-cluster DAGs built
    in bi-etl-ejuice typically set retries from the DAG declaration (cluster
    ``emr_task_retries`` / ``emr_retry_delay_seconds``).
    """

    ui_color = "#f9c915"
    ui_fgcolor = "#000"

    def __init__(
        self,
        job_flow_id: str,
        aws_conn_id: str = "aws_default",
        deferrable: bool = False,
        check_interval: int = EMR_DEFAULT_WAITER_DELAY_SECONDS,
        **kwargs,
    ):
        check_interval_val = kwargs.pop("check_interval", check_interval)
        pool_val = kwargs.pop("pool", EMR_DEFAULT_POOL)
        pool_slots_val = kwargs.pop("pool_slots", EMR_DEFAULT_POOL_SLOTS)
        super().__init__(
            job_flow_id=job_flow_id,
            aws_conn_id=aws_conn_id,
            deferrable=deferrable,
            waiter_delay=check_interval_val,
            pool=pool_val,
            pool_slots=pool_slots_val,
            **kwargs,
        )
