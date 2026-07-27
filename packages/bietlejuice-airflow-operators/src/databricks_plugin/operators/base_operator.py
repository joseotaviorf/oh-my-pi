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
from datetime import datetime, timedelta, timezone
from time import sleep

from airflow.exceptions import AirflowException
from airflow.models import BaseOperator
from six import integer_types, string_types


class QuintoAndarDatabricksBaseOperator(BaseOperator):
    """
    Abstract base class for Databricks operators. To derive this class,
    you are expected to override the constructor as well as the 'execute' method.

    Operators derived from this class should execute requests over Databricks
    API endpoints, sending or retrieveing data or polling over a status endpoint
    for completion while the operation is performed asynchronously inside Databricks.
    """

    XCOM_CLUSTER_ID_KEY = "cluster_id"
    XCOM_CLUSTER_PAGE_URL_KEY = "cluster_page_url"
    XCOM_JOB_ID_KEY = "job_id_{execute_job_cluster_task_id}"
    XCOM_LATEST_REPAIR_ID_KEY = "latest_repair_id"
    XCOM_RUN_ID_KEY = "run_id_{execute_job_cluster_task_id}"
    XCOM_RUN_PAGE_URL_KEY = "run_page_url"
    XCOM_TASK_RUN_ID_KEY = "task_run_id"
    XCOM_OUTPUT_KEY = "output"

    TASK_RETRIES = 3
    API_POLLING_PERIOD_SECONDS = 10
    TASK_EXECUTION_TIMEOUT = timedelta(hours=2)
    TASK_RETRY_DELAY = timedelta(minutes=3)
    TASK_MAX_RETRY_DELAY = timedelta(minutes=7)

    CLUSTER_DEFAULT_PERMISSIONS = [
        {"group_name": "users", "permission_level": "CAN_MANAGE"}
    ]

    ui_color = "#FF3621"
    ui_fgcolor = "#fff"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

    @classmethod
    def _deep_string_coerce(cls, content, json_path="json"):
        """
        Coerces content or all values of content if it is a dict to a string. The
        function will throw if content contains non-string or non-numeric types.

        The reason why we have this function is because the ``self.json`` field must be a
        dict with only string values. This is because ``render_template`` will fail
        for numerical values.
        """
        c = cls._deep_string_coerce
        if isinstance(content, string_types):
            return content
        elif isinstance(content, integer_types + (float,)):
            # Databricks can tolerate either numeric or string types in the API backend.
            return str(content)
        elif isinstance(content, (list, tuple)):
            return [c(e, f"{json_path}[{i}]") for i, e in enumerate(content)]
        elif isinstance(content, dict):
            return {k: c(v, f"{json_path}[{k}]") for k, v in list(content.items())}
        else:
            param_type = type(content)
            raise TypeError(
                f"Type {param_type} used for parameter {json_path} "
                "is not a number or a string"
            )

    def _log_timeout_remaining(self, start_date, execution_timeout):
        """
        Logs timeout settings and remaining time until the task gets timed-out.

        :param start_date: Airflow task start date
        :type start_date: datetime.datetime
        :param execution_timeout: Airflow task time delta in which execution will timeout
        :type execution_timeout: datetime.timedelta
        """
        timeout_timestamp = start_date + execution_timeout
        self.log.info(
            f"timeout_remaining={timeout_timestamp - datetime.now(timezone.utc)}"
        )

    def _check_task_timeout(self, start_date, execution_timeout):
        timeout_timestamp = start_date + execution_timeout
        current_time = datetime.now(timezone.utc)
        if current_time >= timeout_timestamp:
            remaining = current_time - timeout_timestamp
            raise AirflowException(
                f"Task exceeded execution timeout of {execution_timeout}. "
                f"Time exceeded: {remaining}. Clusters still not running."
            )

        return True

    def _wait_polling_period(self, polling_period_seconds):
        """
        Interrupts an execution for the given `polling_period_seconds`.

        :param polling_period_seconds: Seconds to wait until the next poll.
        :type polling_period_seconds: int
        """
        self.log.info(
            f"Next check will be performed in {polling_period_seconds} seconds..."
        )
        sleep(polling_period_seconds)

    def _monitor_clusters_state(
        self,
        databricks_hook,
        cluster_ids: list,
        start_date: datetime,
        execution_timeout: timedelta,
        polling_period_seconds: int,
    ):
        """
        Monitors the state of the clusters provided in `cluster_ids` list. Finishes
        either when all clusters are up and running or when any cluster returns a
        failure state. Waits for the provided `polling_period_seconds` between loops.

        :param databricks_hook: QuintoAndarDatabricksHook instance
        :type databricks_hook: :class:QuintoAndarDatabricksHook
        :param cluster_ids: list of unique identifiers of the clusters whose states
            will be checked.
        :type cluster_ids: list[str]
        :param start_date: Airflow task start date
        :type start_date: datetime.datetime
        :param execution_timeout: Airflow task time delta in which execution will timeout
        :type execution_timeout: datetime.timedelta
        :param polling_period_seconds: Seconds to wait until the next poll.
        :type polling_period_seconds: int
        :rtype: None
        """
        while self._check_task_timeout(start_date, execution_timeout):
            self._log_timeout_remaining(start_date, execution_timeout)
            clusters_states = []
            # TODO: consider applying multithreading to avoid time delays due to sequential requests
            for cluster_id in cluster_ids:
                cluster_state = databricks_hook.get_cluster_state(cluster_id)
                cluster_state.raise_for_state()
                clusters_states.append(cluster_state.is_running)
            if all(clusters_states):
                break
            self._wait_polling_period(polling_period_seconds)

    def _monitor_libraries_installation(
        self,
        databricks_hook,
        cluster_ids: list,
        start_date: datetime,
        execution_timeout: timedelta,
        polling_period_seconds: int,
    ):
        """
        Monitors the state of the libraries to be installed into the clusters provided
        in `cluster_ids` list. Finishes either when all libraries of all clusters are
        installed or when any library of any cluster returns a failure state. Waits for
        the provided `polling_period_seconds` between loops.

        :param databricks_hook: DatabricksHook instance
        :type databricks_hook: :class:DatabricksHook
        :param cluster_ids: list of unique identifiers of the clusters whose libraries
            installation will be checked.
        :type cluster_ids: list[str]
        :param start_date: Airflow task start date
        :type start_date: datetime.datetime
        :param execution_timeout: Airflow task time delta in which execution will timeout
        :type execution_timeout: datetime.timedelta
        :param polling_period_seconds: Seconds to wait until the next poll.
        :type polling_period_seconds: int
        :rtype: None
        """
        clusters_finished = {}
        libs_status = {}
        while self._check_task_timeout(start_date, execution_timeout):
            self._log_timeout_remaining(start_date, execution_timeout)
            for cluster_id in cluster_ids:
                libs_status[cluster_id] = (
                    databricks_hook.check_libraries_cluster_status(
                        cluster_id=cluster_id, last_libs_status=libs_status
                    )
                )
                clusters_finished[cluster_id] = all(libs_status[cluster_id].values())
                if clusters_finished[cluster_id]:
                    self.log.info(
                        "All libraries have been successfully installed "
                        f"in cluster ID '{cluster_id}'."
                    )
            if all(clusters_finished.values()):
                self.log.info(
                    "All libraries of all clusters have been successfully installed."
                )
                break
            self._wait_polling_period(polling_period_seconds)

    def _terminate_running_cluster(self, databricks_hook, cluster_id):
        """
        Forces the termination of the provided cluster if it is still running.
        Raises an error if the cluster is currently in a failure state.

        :param databricks_hook: DatabricksHook instance
        :type databricks_hook: :class:DatabricksHook
        :param cluster_id: unique identifier of the cluster to be terminated.
        :type cluster_id: str
        :rtype: None
        """
        cluster_state = databricks_hook.get_cluster_state(cluster_id)
        cluster_state.raise_for_state(fail_on_terminated=False)
        if cluster_state.is_running:
            databricks_hook.terminate_cluster(cluster_id)
