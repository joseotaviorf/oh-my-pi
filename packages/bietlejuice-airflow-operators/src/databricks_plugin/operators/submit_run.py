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
from databricks_plugin.operators.base_operator import QuintoAndarDatabricksBaseOperator
from databricks_plugin.states.errors import (
    DatabricksNotFoundError,
    DatabricksTerminalStateError,
)


class QuintoAndarDatabricksSubmitRunOperator(QuintoAndarDatabricksBaseOperator):
    """
    Submits a one-time run, allowing the run of a workload directly without creating a
    job. May create a new cluster (Jobs Compute workload) for the task run or may use
    an existing cluster (All-Purpose Compute workload). Also, checks periodically the
    state of the run, retrieving its outputs when succeeded or its errors when failed.

    Docs:
    - [Databricks API: Runs submit](https://docs.databricks.com/dev-tools/api/2.0/jobs.html#runs-submit)

    :param json: (templated) A JSON object containing API parameters which will be
        passed directly to the `api/2.0/jobs/runs/submit` endpoint. The other named
        parameters (i.e. `spark_jar_task`, `notebook_task`..) to this operator will
        be merged with this json dictionary if they are provided.
        If there are conflicts during the merge, the named parameters will take
        precedence and override the top level JSON keys.
        e.g.:
        json = {
            "run_name": "My Spark Script Run",
            "spark_python_task": {
                "python_file": s3:/my_bucket/my_spark_script.py",
                "parameters": [
                    "prod",
                    "{{ ds }}",
                    "table",
                ],
            },
            "existing_cluster_id": "My-Cluster-0001"
        },
    :type json: dict
    :param run_name: The name used for this task's run. Defaults to the Airflow's task
        `task_id`. Overrides the `run_name` set in the `json` argument.
    :type run_name: string
    :param notebook_task: The notebook path and parameters for the notebook
        task. This field may not be specified in conjunction with `spark_jar_task`.
        .. seealso::
        - [SparkNotebookTask](https://docs.databricks.com/dev-tools/api/2.0/jobs.html#jobsnotebooktask)
    :type notebook_task: dict
    :param spark_jar_task: The main class and parameters for the JAR task.
        Note that the actual JAR is specified in the `libraries`.
        This field may not be specified in conjunction with `notebook_task`.
        .. seealso::
        - [SparkJarTask](https://docs.databricks.com/dev-tools/api/2.0/jobs.html#jobssparkjartask)
    :type spark_jar_task: dict
    :param spark_python_task: the Python file path and parameters for the
        Python task.
        .. seealso::
        - [SparkPythonTask](https://docs.databricks.com/dev-tools/api/2.0/jobs.html#sparkpythontask)
    :type spark_python_task: dict
    :param spark_submit_task: a dict with parameters to be submitted to
        Spark as a job using the `spark-submit` command. You can invoke a Spark submit
        task only on new clusters.
        .. seealso::
        - [SparkSubmitTask](https://docs.databricks.com/dev-tools/api/2.0/jobs.html#sparksubmittask)
    :type spark_submit_task: dict
    :param timeout_seconds: The timeout for the run. Defaults to 0, meaning no timeout.
    :type timeout_seconds: integer
    :param existing_cluster_id: the ID of an existing cluster that will be used for all
        runs of this job. When running jobs on an existing cluster, you may need to
        manually restart the cluster if it stops responding. When you submit a job run
        on an existing all-purpose cluster, it is treated as an All-Purpose Compute
        (interactive) workload subject to All-Purpose Compute pricing.
        This field may not be specified in conjunction with `new_cluster`.
    :type existing_cluster_id: string
    :param new_cluster: A JSON object containing cluster specifications,
        which will be used as a new cluster to which the run will be submitted.
        The `new_cluster` will take precedence and override any other existing clusters,
        and IS NOT sent together with the `existing_cluster_id`. When you submit a job
        run on a new cluster, the job is treated as a Jobs Compute (automated) workload
        subject to Jobs Compute pricing.
        e.g.: new_cluster = {
            "cluster_name": "CLUSTER_NAME",
            "autoscale": {"min_workers": 3, "max_workers": 4},
            "spark_version": "10.4.x-scala2.12",
            "aws_attributes": {
                "first_on_demand": 1,
                "availability": "SPOT_WITH_FALLBACK",
                "zone_id": "ZONE_ID",
                "instance_profile_arn": "INSTANCE_PROFILE_ARN",
                "spot_bid_price_percent": 100,
                "ebs_volume_count": 0,
            },
            "node_type_id": "i3.xlarge",
            "driver_node_type_id": "i3.xlarge",
            "spark_env_vars": {"PYSPARK_PYTHON": "/databricks/python3/bin/python3"},
            "autotermination_minutes": 10,
            "enable_elastic_disk": True,
        }
        .. seealso::
        - [NewCluster](https://docs.databricks.com/dev-tools/api/2.0/jobs.html#jobsclusterspecnewcluster)
    :type new_cluster: dict
    :param libraries: A JSON object list containing the libraries to be
        installed into the newly created cluster and used within the work of the run.
        e.g.: libraries = [{
            "whl": "s3://BUCKET/CUSTOM.WHL"
        },
        {
            "jar": "s3://BUCKET/CUSTOM.JAR"
        }]
        .. seealso::
        - [ManagedLibraries](https://docs.databricks.com/dev-tools/api/latest/libraries.html#managedlibrarieslibrary)
    :type libraries: list
    :param access_control_list: A JSON object list containing permission parameters
        which will be applied onto the newly created cluster. When not set, the default
        `CLUSTER_DEFAULT_PERMISSIONS` permissions will be used.
        e.g.: access_control_list=[{
            "user_name": "name@example.com",
            "permission_level": "CAN_RESTART"
        },
        {
            "group_name": "group_name",
            "permission_level": "CAN_MANAGE"
        }]
    :type access_control_list: list
    :param databricks_conn_id: The name of the Airflow connection to use.
        By default and in the common case this will be `databricks_default`. To use
        token based authentication, provide the key `token` in the extra field for
        the connection.
    :type databricks_conn_id: string
    :param polling_period_seconds: Controls the rate which the task polls for the
        result each request made. When not set, the default `API_POLLING_PERIOD_SECONDS`
        value (10 seconds) will be used as the waiting time between any recurrent
        requests inside the operator.
    :type polling_period_seconds: int
    :param retries: the number of Airflow task retries that should be performed before
        failing the task. When not set, the default `TASK_RETRIES` value (1) will be
        used as the number of maximum retries for the task.
    :type retries: int
    :param retry_delay: delay between Airflow task retries. When not set, the default
        `TASK_RETRY_DELAY` value (3 minutes) will be used as waiting time between
        task retries.
    :type retry_delay: datetime.timedelta
    :param retry_exponential_backoff: enables Airflow to perform retries waiting for
        intervals that grow exponentially and also with an increment of a jitter value.
        This avoids the client request traffic to overload servers. Defaults to `True`.
    :param max_retry_delay: maximum delay interval between Airflow task retries. Only
        Used when `retry_exponential_backoff` is set to `True`. When not set, the default
        `TASK_MAX_RETRY_DELAY` value (7 minutes) will be used as the highest waiting
        time between task retries. When this interval is reached, it is used for all
        retries remaining.
    :type max_retry_delay: datetime.timedelta
    :param execution_timeout: the airflow BaseOperator execution_timeout. When not set
        the default `TASK_EXECUTION_TIMEOUT` (2 hours) will be set.
        When set as `None` then no timeout will be applied (not recommended).
    :type execution_timeout: datetime.timedelta
    """

    template_fields = ("json",)
    ui_color = "#FF6952"
    ui_fgcolor = "#fff"

    def __init__(
        self,
        json: dict = None,
        run_name: str = None,
        notebook_task: dict = None,
        spark_jar_task: dict = None,
        spark_python_task: dict = None,
        spark_submit_task: dict = None,
        timeout_seconds: int = None,
        existing_cluster_id: str = None,
        new_cluster: dict = None,
        libraries: list = None,
        access_control_list: list = QuintoAndarDatabricksBaseOperator.CLUSTER_DEFAULT_PERMISSIONS,
        databricks_conn_id: str = "databricks_default",
        polling_period_seconds: int = QuintoAndarDatabricksBaseOperator.API_POLLING_PERIOD_SECONDS,
        do_output_xcom_push=False,
        retries: int = QuintoAndarDatabricksBaseOperator.TASK_RETRIES,
        retry_delay=QuintoAndarDatabricksBaseOperator.TASK_RETRY_DELAY,
        retry_exponential_backoff: bool = True,
        max_retry_delay=QuintoAndarDatabricksBaseOperator.TASK_MAX_RETRY_DELAY,
        execution_timeout=QuintoAndarDatabricksBaseOperator.TASK_EXECUTION_TIMEOUT,
        **kwargs,
    ):
        """
        Creates a new `QuintoAndarDatabricksSubmitRunOperator`.
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
        self.libraries = libraries or []
        self.access_control_list = access_control_list
        self.databricks_conn_id = databricks_conn_id
        self.json = json or {}

        self.run_id = None
        self.cluster_id = None
        self._cluster_resolved = False

        if run_name or "run_name" not in self.json:
            self.json["run_name"] = run_name or self.task_id

        if notebook_task:
            self.json["notebook_task"] = notebook_task
        if spark_jar_task:
            self.json["spark_jar_task"] = spark_jar_task
        if spark_python_task:
            self.json["spark_python_task"] = spark_python_task
        if spark_submit_task:
            self.json["spark_submit_task"] = spark_submit_task
        if timeout_seconds:
            self.json["timeout_seconds"] = timeout_seconds

        if new_cluster:
            self.json["new_cluster"] = new_cluster
        elif existing_cluster_id:
            self.json["existing_cluster_id"] = existing_cluster_id
        if libraries:
            self.json["libraries"] = libraries
        self.do_output_xcom_push = do_output_xcom_push

    def pre_execute(self, context):
        """
        Performs run's existing cluster validation and startup.
        """
        self._resolve_cluster(context)

    def _resolve_cluster(self, context):
        """Resolve cluster config from JSON/XCom; start cluster if terminated.

        Idempotent: safe to call from both pre_execute and execute.
        Needed because Astronomer Airflow 2.11+ may skip pre_execute.
        """
        if self._cluster_resolved:
            return
        self.json = self._deep_string_coerce(self.json)

        if self.json.get("new_cluster"):
            self._cluster_resolved = True
            return

        self.cluster_id = self.json.get(
            "existing_cluster_id",
            self.xcom_pull(context, key=self.XCOM_CLUSTER_ID_KEY),
        )
        if not self.cluster_id:
            raise DatabricksNotFoundError(
                "Cluster ID was not found to submit the run '{}'.".format(
                    self.json.get("run_name")
                )
            )

        self.log.info(f"Using provided Cluster ID '{self.cluster_id}'...")
        self.json["existing_cluster_id"] = self.cluster_id

        cluster_state = self.databricks_hook.get_cluster_state(self.cluster_id)
        if cluster_state.is_terminated:
            execution_timeout = context["task"].execution_timeout
            start_date = context["ti"].start_date

            self._log_timeout_remaining(start_date, execution_timeout)
            self.databricks_hook.start_cluster(self.cluster_id)
            self._monitor_clusters_state(
                self.databricks_hook,
                [self.cluster_id],
                start_date,
                execution_timeout,
                self.polling_period_seconds,
            )
            if self.access_control_list:
                self.databricks_hook.grant_permissions(
                    entity_type="clusters",
                    entity_id=self.cluster_id,
                    access_control_list=self.access_control_list,
                )
            if self.libraries:
                self.databricks_hook.install_libraries(self.cluster_id, self.libraries)
            self._monitor_libraries_installation(
                self.databricks_hook,
                [self.cluster_id],
                start_date,
                execution_timeout,
                self.polling_period_seconds,
            )
        self._cluster_resolved = True

    def execute(self, context):
        """
        Performs main requests for a run submit:

        1. Submits a run using the JSON payload generated (or provided);
        2. Retrieves and logs the Run Page URL (also available as an XCOM);
        3. When a new cluster is provided:
         3.1 gets the `cluster_id` parameter from the newly job run;
         3.2 monitors the cluster startup;
        4. Periodically checks the state of the run;
        5. Logs either the output or the error and stack trace when done.
        """
        self._resolve_cluster(context)
        execution_timeout = context["task"].execution_timeout
        start_date = context["ti"].start_date

        self.run_id = self.databricks_hook.submit_run(self.json)
        job_run = self.databricks_hook.get_job_run(self.run_id)
        job_id = job_run.get("job_id")
        run_page_url = self.databricks_hook.get_job_run_page_url(self.run_id)
        self.xcom_push(context, key=self.XCOM_RUN_PAGE_URL_KEY, value=run_page_url)

        if self.access_control_list:
            # The job's ACL is the same as the cluster, but CAN_ATTACH_TO should be CAN_VIEW instead
            job_access_control_list = self._replace_attach_permission_with_view(
                self.access_control_list
            )
            self.log.info(
                f"Granting {str(job_access_control_list)} ACL to job {job_id}..."
            )
            self.databricks_hook.grant_permissions(
                entity_type="jobs",
                entity_id=job_id,
                access_control_list=job_access_control_list,
            )

        if self.json.get("new_cluster"):
            self.cluster_id = self.databricks_hook.get_single_task_job_cluster_id(
                self.run_id,
                polling_period_seconds=self.polling_period_seconds,
                start_date=start_date,
                execution_timeout=execution_timeout,
            )
            self._monitor_clusters_state(
                self.databricks_hook,
                [self.cluster_id],
                start_date,
                execution_timeout,
                self.polling_period_seconds,
            )

        while self._check_task_timeout(start_date, execution_timeout):
            self._log_timeout_remaining(start_date, execution_timeout)
            run_state = self.databricks_hook.get_job_run_state(self.run_id)
            try:
                run_state.raise_for_state()
            except DatabricksTerminalStateError as ex:
                run_error_and_trace = self.databricks_hook.get_job_run_error_and_trace(
                    self.run_id
                )
                self.log.error(
                    "Error stack trace:"
                    + "\n{}".format(run_error_and_trace["error_trace"])
                    + "\n--------------------------------------------------------------------------------"
                )
                raise ex from None
            if run_state.is_successful:
                run_output = self.databricks_hook.get_job_run_logs(self.run_id)
                self.log.info(
                    "Run '{}' successfully completed with output:".format(
                        self.json.get("run_name")
                    )
                    + "\n--------------------------------------------------------------------------------"
                    + f"\n{run_output}"
                    + "\n--------------------------------------------------------------------------------"
                )
                if self.do_output_xcom_push:
                    if run_output:
                        context["ti"].xcom_push(
                            key=self.XCOM_OUTPUT_KEY, value=run_output
                        )
                break
            self._wait_polling_period(self.polling_period_seconds)

    def on_kill(self):
        """
        Forces the cancellation of the submitted rum, when it exists.
        """
        if self.run_id:
            self.databricks_hook.cancel_job_run(self.run_id)
        else:
            self.log.warn("No Run ID was found to be cancelled.")

    def _replace_attach_permission_with_view(self, access_control_list):
        """
        Replaces the `CAN_ATTACH_TO` permission level with `CAN_VIEW` in the provided list.
        This allows the same ACL to be used for both clusters and jobs.
        """
        return [
            {**acl, "permission_level": "CAN_VIEW"}
            if acl["permission_level"] == "CAN_ATTACH_TO"
            else acl
            for acl in access_control_list
        ]
