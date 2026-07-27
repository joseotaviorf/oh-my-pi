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
from airflow.utils.decorators import apply_defaults
from requests.exceptions import HTTPError

from databricks_plugin.hooks.databricks_hook import (
    JOBS_API_VERSION,
    QuintoAndarDatabricksHook,
)
from databricks_plugin.operators.base_operator import QuintoAndarDatabricksBaseOperator
from databricks_plugin.states.errors import DatabricksTerminalStateError


class QuintoAndarDatabricksCheckJobTaskOperator(QuintoAndarDatabricksBaseOperator):
    """
    Checks periodically the state of a task executed within a Databricks job run,
    retrieving its errors when failed.

    Docs:
    - [Databricks Jobs docs](https://docs.databricks.com/workflows/jobs/jobs.html)
    - [Databricks API: Get single job run](https://docs.databricks.com/api-explorer/workspace/jobs/getrun)
    - [Databricks API: Get job run output](https://docs.databricks.com/api-explorer/workspace/jobs/getrunoutput)

    :param json: (templated) A JSON object containing task specifications, which will
        be used as the job's cluster.
        e.g.:
        json = {
            "spark_python_task": {
                "python_file": s3:/my_bucket/my_spark_script.py",
                "parameters": [
                    "prod",
                    "{{ ds }}",
                    "table",
                ],
            }
        },
    :type json: dict
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

    TASK_RETRIES = 2

    template_fields = ("json",)
    ui_color = "#FF6952"
    ui_fgcolor = "#fff"

    @apply_defaults
    def __init__(
        self,
        json: list,
        databricks_conn_id="databricks_default",
        polling_period_seconds=QuintoAndarDatabricksBaseOperator.API_POLLING_PERIOD_SECONDS,
        retries=TASK_RETRIES,
        retry_delay=QuintoAndarDatabricksBaseOperator.TASK_RETRY_DELAY,
        retry_exponential_backoff=True,
        max_retry_delay=QuintoAndarDatabricksBaseOperator.TASK_MAX_RETRY_DELAY,
        execution_timeout=QuintoAndarDatabricksBaseOperator.TASK_EXECUTION_TIMEOUT,
        **kwargs,
    ):
        """
        Creates a new ``QuintoAndarDatabricksCheckJobTaskOperator``.
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
        self.polling_period_seconds = polling_period_seconds
        self.databricks_conn_id = databricks_conn_id
        self.databricks_hook = None
        self.json = json
        self.run_id = None
        self.execute_job_cluster_task_id = None

    def pre_execute(self, context):
        """
        1. Creates a databricks_hook instance;
        2. Gets the job_id from the XCom key.
        3. Gets the run_id from the XCom key.
        """
        self.databricks_hook = QuintoAndarDatabricksHook(self.databricks_conn_id)
        self.execute_job_cluster_task_id = self._get_execute_job_cluster_task_id()

        if not self.execute_job_cluster_task_id:
            raise Exception(
                "m=pre_execute, error=Failed to find `execute-job-cluster` task, make sure that this is a JobCluster DAG."
            )

        self.job_id = self.xcom_pull(
            context,
            key=self.XCOM_JOB_ID_KEY.format(
                execute_job_cluster_task_id=self.execute_job_cluster_task_id
            ),
        )
        self.run_id = self.xcom_pull(
            context,
            key=self.XCOM_RUN_ID_KEY.format(
                execute_job_cluster_task_id=self.execute_job_cluster_task_id
            ),
        )

    def execute(self, context):
        """
        Performs main requests to check and handle errors of a job task execution:

        1. Retrieves state of the latest task attempt;
        2. If the task is in a failed state:
         2.1 cancels the whole job run execution;
         2.2 monitors the job run execution to assure it's terminated;
         2.3 calls the repair request;
        3. Retrieves the run ID of the latest task attempt (renewed when job is repaired);
        4. Uses the task run ID to generate a run page URL, pushed into an XCom;
        5. Monitors the execution of the task;
        6. If the task fails:
         6.1 retrieves and logs error and stack trace;
         6.2 raises exception without traceback, to reduce verbosity on Airflow logs UI.
        """
        execution_timeout = context["task"].execution_timeout
        start_date = context["ti"].start_date

        job_run_task_state = self.databricks_hook.get_job_run_task_state(
            self.run_id, self.task_id, version=JOBS_API_VERSION
        )
        try:
            job_run_task_state.raise_for_state()
        except DatabricksTerminalStateError:
            self.databricks_hook.cancel_job_run(self.run_id, version=JOBS_API_VERSION)
            self.task_run_id = self.databricks_hook.get_job_run_task_run_id(
                self.run_id, self.task_id, version=JOBS_API_VERSION
            )
            self._monitor_latest_repair_execution(
                self.run_id, self.task_run_id, start_date, execution_timeout
            )
            self._request_repair(self.run_id, context)

        self.task_run_id = self.databricks_hook.get_job_run_task_run_id(
            self.run_id, self.task_id, version=JOBS_API_VERSION
        )
        run_page_url = self.databricks_hook.generate_run_page_url(
            self.job_id, self.task_run_id
        )
        self.xcom_push(context, key=self.XCOM_RUN_PAGE_URL_KEY, value=run_page_url)

        while self._check_task_timeout(start_date, execution_timeout):
            self._log_timeout_remaining(start_date, execution_timeout)
            job_run_task_state = self.databricks_hook.get_job_run_task_state(
                self.run_id, self.task_id, version=JOBS_API_VERSION
            )
            try:
                job_run_task_state.raise_for_state()
            except DatabricksTerminalStateError as ex:
                run_error_and_trace = self.databricks_hook.get_job_run_error_and_trace(
                    self.task_run_id, version=JOBS_API_VERSION
                )
                self.log.error(
                    "Error stack trace:"
                    + "\n{}".format(run_error_and_trace["error_trace"])
                    + "\n--------------------------------------------------------------------------------"
                )
                raise ex from None
            if job_run_task_state.is_successful:
                break
            self._wait_polling_period(self.polling_period_seconds)

    def _monitor_latest_repair_execution(
        self, run_id, task_run_id, start_date, execution_timeout
    ):
        """
        Monitors if the job run of the provided run task ID is terminated, polling
        to retrieve the current task run status, during the time interval between the
        provided `start_date` and `execution_timeout`.

        :param run_id: The canonical identifier of the run for which to retrieve the state.
        :type run_id: integer
        :param start_date: Airflow task start date
        :type start_date: datetime.datetime
        :param execution_timeout: Airflow task time delta in which execution will timeout
        :type execution_timeout: datetime.timedelta
        :rtype: None
        """
        while self._check_task_timeout(start_date, execution_timeout):
            self._log_timeout_remaining(start_date, execution_timeout)
            repair_state = self.databricks_hook.get_task_repair_state(
                run_id, task_run_id, version=JOBS_API_VERSION
            )
            if repair_state.is_terminal:
                break
            self._wait_polling_period(5)

    def _request_repair(self, run_id, context):
        """
        Performs the repair request by retrieving the `latest_repair_id`, using it
        in the repair call and pushing the new repair ID into an XCom.
        If the repair request returns a "Repair is not allowed on an active run" error,
        it logs a warning message instead of raising the exception.

        :param run_id: The canonical identifier of the run for which to send the repair.
        :type run_id: integer
        :param context: Airflow execution context object
        :type context: dict
        :rtype: None
        """
        latest_repair_id = self.databricks_hook.get_repair_id(run_id)
        try:
            latest_repair_id = self.databricks_hook.repair_job_run(
                run_id, latest_repair_id, rerun_all_failed_tasks=True
            )
            self.xcom_push(
                context, key=self.XCOM_LATEST_REPAIR_ID_KEY, value=latest_repair_id
            )
            self._wait_polling_period(self.polling_period_seconds)
        except HTTPError as ex:
            if "Repair is not allowed on an active run" in ex.args[0]:
                self.log.warn(
                    "Repair not started: the job run is currently active and running "
                    "either as the original run or as a previous repair."
                )
            else:
                raise ex

    def _get_execute_job_cluster_task_id(self, task=None) -> str:
        """
        Finds and returns task that uses QuintoAndarDatabricksExecuteJobClusterOperator.
        Return None in case that the task does not exists.
        """
        # We need to import this here to avoid a circular dependency
        from databricks_plugin.operators.execute_job_cluster import (
            QuintoAndarDatabricksExecuteJobClusterOperator,
        )

        task = task or self
        if isinstance(task, QuintoAndarDatabricksExecuteJobClusterOperator):
            return task.task_id
        if task.upstream_list:
            return self._get_execute_job_cluster_task_id(task.upstream_list[0])
        return None
