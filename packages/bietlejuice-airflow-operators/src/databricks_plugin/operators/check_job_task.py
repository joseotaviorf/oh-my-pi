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
from requests.exceptions import HTTPError

from databricks_plugin.hooks.databricks_hook import JOBS_API_VERSION
from databricks_plugin.operators.base_operator import QuintoAndarDatabricksBaseOperator
from databricks_plugin.states.errors import DatabricksTerminalStateError


class QuintoAndarDatabricksCheckJobTaskOperator(QuintoAndarDatabricksBaseOperator):
    """
    This operator is made specifically to be used in JobCluster DAGs.

    Checks for specific task_id is in a bad state - like ``FAILED`` or ``CANCELLED``.

    A use case is if we have a
    data_ingestion_task --> preprocessing_task --> spark-submit

    We'd need to run a check like
    data_ingestion_task --> preprocessing_task --> spark-submit --> check_preprocessing_task

    where we check if the preprocessing task executed properly and repair the run if not.

    The repair (or retry) is useful for when we have cluster-related issues like
    NotEnoughResources or spot instance interruptions.

    In Airflow, this task is not required for every spark-task, but it's a good practice to
    add it for longer jobs. This is because when retrying, Airflow will resubmit the DAG to
    the cluster as a new job run. Which will create a new cluster, rerun all tasks and then
    reach your spark task. This would create an even more considerable cost. Especially given
    that the time spent provisioning and warming up the cluster may exceed the task itself.

    Another thing to note is that this task is not idempotent. If you run it twice, it will
    repair the job twice. This is because we don't have a way to check if a repair has already
    been done. So, if you run this task twice, it will repair the job twice. This is not a
    problem for the Airflow DAG, but it's something to keep in mind.

    This operator requires a task to be launched first:

    **Example**::

        t1 = QuintoAndarDatabricksExecuteJobClusterOperator(
            task_id="execute_job_cluster",
            ...
        )
        t2 = QuintoAndarDatabricksSubmitRunJobClusterOperator(
            task_id="task-id",
            ...
        )
        t3 = QuintoAndarDatabricksCheckJobTaskOperator(
            task_id="check-task-id",
            ...
        )
        t1 >> t2 >> t3

    .. seealso::
        For more information on how to use this operator, take a look at the guide:
        :ref:`howto/operator:QuintoAndarDatabricksCheckJobTaskOperator`
    """

    TASK_RETRIES = 2

    template_fields = ("json",)
    ui_color = "#FF6952"
    ui_fgcolor = "#fff"

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
        self.json = json
        self.run_id = None
        self.execute_job_cluster_task_id = None
        self.job_id = None

    def pre_execute(self, context):
        """
        1. Gets the job_id from the XCom key.
        2. Gets the run_id from the XCom key.
        """
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
        # Guard: ensure run_id and job_id are available even if pre_execute was skipped
        if not self.execute_job_cluster_task_id:
            self.execute_job_cluster_task_id = self._get_execute_job_cluster_task_id()
        if not self.execute_job_cluster_task_id:
            raise Exception(
                "m=execute, error=Failed to find `execute-job-cluster` task, "
                "make sure that this is a JobCluster DAG."
            )
        if self.job_id is None:
            self.job_id = self.xcom_pull(
                context,
                key=self.XCOM_JOB_ID_KEY.format(
                    execute_job_cluster_task_id=self.execute_job_cluster_task_id
                ),
            )
        if self.run_id is None:
            self.run_id = self.xcom_pull(
                context,
                key=self.XCOM_RUN_ID_KEY.format(
                    execute_job_cluster_task_id=self.execute_job_cluster_task_id
                ),
            )
        if self.run_id is None:
            raise Exception(
                f"m=execute, error=run_id is None after XCom pull. "
                f"XCom key: {self.XCOM_RUN_ID_KEY.format(execute_job_cluster_task_id=self.execute_job_cluster_task_id)}"
            )

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
        """
        while self._check_task_timeout(start_date, execution_timeout):
            self._log_timeout_remaining(start_date, execution_timeout)

            job_run_task_state = self.databricks_hook.get_job_run_task_state(
                run_id, self.task_id, version=JOBS_API_VERSION
            )
            if job_run_task_state.is_terminal:
                break
            self._wait_polling_period(5)

    def _request_repair(self, run_id, context):
        """
        Requests repair of a specific job run by retrieving the latest_repair_id,
        issuing the repair call, and pushing the new repair ID into XCom.
        """
        latest_repair_id = self.databricks_hook.get_repair_id(run_id)
        try:
            latest_repair_id = self.databricks_hook.repair_job_run(
                run_id,
                latest_repair_id=latest_repair_id,
                rerun_tasks=[self.task_id],
                version=JOBS_API_VERSION,
            )
            self.xcom_push(
                context, key=self.XCOM_LATEST_REPAIR_ID_KEY, value=latest_repair_id
            )
            self._wait_polling_period(self.polling_period_seconds)
        except HTTPError as ex:
            # RESOURCE_CONFLICT: the run is already being repaired — safe to ignore,
            # the next retry will pick up the in-progress repair.
            if ex.response.status_code == 409:
                self.log.error(
                    f"m=execute task={self.task_id} error=Run {run_id} has already "
                    "been repaired; will check for latest task "
                    f"attempt on retry. HTTPError={ex.response.text}"
                )
                return
            # Repair is not allowed on an active run: the run/task is still transitioning
            # out of its terminal state (e.g. cancellation not yet propagated) or is already
            # being repaired by another operator invocation.
            if ex.response.status_code == 400 and (
                "Repair is not allowed on an active run" in ex.response.text
            ):
                self.log.error(
                    f"m=execute task={self.task_id} error=Run {run_id} is already "
                    "running; will check for latest task "
                    f"attempt on retry. HTTPError={ex.response.text}"
                )
                return
            raise

    def _get_execute_job_cluster_task_id(self, task=None) -> str:
        """
        Gets the id of the execute_job_cluster_operator task that this operator depends on
        recursively through the parents.
        """
        from databricks_plugin.operators.execute_job_cluster import (
            QuintoAndarDatabricksExecuteJobClusterOperator,
        )

        if task is None:
            task = self

        for parent in task.upstream_list:
            if isinstance(parent, QuintoAndarDatabricksExecuteJobClusterOperator):
                return parent.task_id
            return self._get_execute_job_cluster_task_id(parent)
        return None
