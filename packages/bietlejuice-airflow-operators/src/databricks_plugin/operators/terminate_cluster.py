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
from airflow.exceptions import AirflowNotFoundException

from databricks_plugin.operators.base_operator import QuintoAndarDatabricksBaseOperator


class QuintoAndarDatabricksTerminateClusterOperator(QuintoAndarDatabricksBaseOperator):
    """
    Terminates a Databricks Spark cluster using either a provided cluster ID or trying to
    retrieve one from a `cluster_id` DAG XCom.

    Docs:
    - [Databricks API 2.0: Clusters delete](https://docs.databricks.com/api/latest/clusters.html#delete)

    :param cluster_id: (templated) The ID of the cluster which will be terminated.
        When not set, it the default is `None` and the operator tries to retrieve the
        cluster ID from the `cluster_id` DAG XCom.
    :type cluster_id: str
    :param databricks_conn_id: The name of the Airflow connection to use.
        By default and in the common case this will be ``databricks_default``. To use
        token based authentication, provide the key ``token`` in the extra field for
        the connection.
    :type databricks_conn_id: string
    :param polling_period_seconds: Controls the rate which the task polls for the
        result each request made. When not set the default `API_POLLING_PERIOD_SECONDS`
        value (10 seconds) will be used as the waiting time between any recurrent
        requests inside the operator.
    :type polling_period_seconds: int
    :param retries: the number of Airflow task retries that should be performed before
        failing the task. When not set the default `TASK_RETRIES` value (1) will be
        used as the number of maximum retries for the task.
    :type retries: int
    :param retry_delay: delay between Airflow task retries. When not set the default
        `TASK_RETRY_DELAY` value (3 minutes) will be used as waiting time between
        task retries.
    :type retry_delay: datetime.timedelta
    :param retry_exponential_backoff: enables Airflow to perform retries waiting for
        intervals that grow exponentially and also with an increment of a jitter value.
        This avoids the client request traffic to overload servers. Defaults to `True`.
    :type retry_exponential_backoff: bool
    :param max_retry_delay: maximum delay interval between Airflow task retries. Only
        Used when `retry_exponential_backoff` is set to `True`. When not set the default
        `TASK_MAX_RETRY_DELAY` value (7 minutes) will be used as the highest waiting
        time between task retries. When this interval is reached, it is used for all
        retries remaining.
    :type max_retry_delay: datetime.timedelta
    :param execution_timeout: the airflow BaseOperator execution_timeout. When not set
        the default `TASK_EXECUTION_TIMEOUT` (2 hours) will be set.
        When set as `None` then no timeout will be applied (not recommended).
    :type execution_timeout: datetime.timedelta
    """

    template_fields = ("cluster_id",)
    ui_color = "#FF3621"
    ui_fgcolor = "#fff"

    def __init__(
        self,
        cluster_id=None,
        databricks_conn_id="databricks_default",
        polling_period_seconds=QuintoAndarDatabricksBaseOperator.API_POLLING_PERIOD_SECONDS,
        retries=QuintoAndarDatabricksBaseOperator.TASK_RETRIES,
        retry_delay=QuintoAndarDatabricksBaseOperator.TASK_RETRY_DELAY,
        retry_exponential_backoff=True,
        max_retry_delay=QuintoAndarDatabricksBaseOperator.TASK_MAX_RETRY_DELAY,
        execution_timeout=QuintoAndarDatabricksBaseOperator.TASK_EXECUTION_TIMEOUT,
        **kwargs,
    ):
        """
        Creates a new ``QuintoAndarDatabricksTerminateClusterOperator``.
        """
        kwargs = {
            **kwargs,
            "retries": retries,
            "retry_delay": retry_delay,
            "retry_exponential_backoff": retry_exponential_backoff,
            "max_retry_delay": max_retry_delay,
            "execution_timeout": execution_timeout,
        }
        super().__init__(**kwargs)
        self.cluster_id = cluster_id
        self.databricks_conn_id = databricks_conn_id
        self.polling_period_seconds = polling_period_seconds

    def pre_execute(self, context):
        """
        Gets the cluster_id from the XCom key.
        """
        self.cluster_id = self.cluster_id or self.xcom_pull(
            context, key=self.XCOM_CLUSTER_ID_KEY
        )

    def execute(self, context):
        # Guard: pull cluster_id from XCom if pre_execute was skipped (Astro 2.11+)
        if not self.cluster_id:
            self.cluster_id = self.xcom_pull(context, key=self.XCOM_CLUSTER_ID_KEY)
        execution_timeout = context["task"].execution_timeout
        start_date = context["ti"].start_date

        if not self.cluster_id:
            raise AirflowNotFoundException(
                f"No cluster ID found in DAG XCom '{self.XCOM_CLUSTER_ID_KEY}'"
            )

        self.log.info(
            f"Using cluster ID '{self.cluster_id}' from "
            f"'{self.XCOM_CLUSTER_ID_KEY}' DAG XCom..."
        )
        self.databricks_hook.terminate_cluster(self.cluster_id)

        while self._check_task_timeout(start_date, execution_timeout):
            self._log_timeout_remaining(start_date, execution_timeout)
            cluster_state = self.databricks_hook.get_cluster_state(self.cluster_id)
            cluster_state.raise_for_state(fail_on_terminated=False)
            if cluster_state.is_terminated:
                break
            self._wait_polling_period(self.polling_period_seconds)
