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
import re

from databricks_plugin.hooks.databricks_hook import JOBS_API_VERSION
from databricks_plugin.operators.base_operator import QuintoAndarDatabricksBaseOperator
from databricks_plugin.operators.check_job_task import (
    QuintoAndarDatabricksCheckJobTaskOperator,
)


class QuintoAndarDatabricksExecuteJobClusterOperator(QuintoAndarDatabricksBaseOperator):
    """
    Creates and executes a Databricks job with a list of tasks inside a static provided cluster,
    installing specific libraries and applying specific Access Control Lists.

    You can create jobs only in a Data Science & Engineering workspace or
    a Machine Learning workspace.
    A workspace is limited to 1000 concurrent job runs. A `429 Too Many Requests`
    response is returned when you request a run that cannot start immediately.
    The number of jobs a workspace can create in an hour is limited to 10000.

    Docs:
    - [Databricks Jobs docs](https://docs.databricks.com/workflows/jobs/jobs.html)
    - [Databricks API: Jobs create](https://docs.databricks.com/dev-tools/api/latest/jobs.html#operation/JobsCreate)
    - [Databricks API: Libraries install](https://docs.databricks.com/api/latest/libraries.html#install)

    :param cluster_configuration: (templated) A JSON object containing cluster
        specifications, which will be used as the job's cluster.
        e.g.: cluster_configuration = {
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
    :type cluster_configuration: dict
    :param tasks: (templated) An optional JSON object list of task specifications to be
        executed by this job. This task list is not required. It is already created
        automatically by retrieving all `QuintoAndarDatabricksCheckJobTaskOperator`
        tasks attached as downstream dependencies of this operator.
        If provided, must contain at least the following keys:
        - task_key: A unique name for the task. This field is used to refer to this
            task from other tasks. This field is required and must be unique within
            its parent job. The maximum length is 100 characters.
        - depends_on: An optional JSON object specifying the dependency graph of the
            task. All tasks specified in this field must complete successfully before
            executing this task. The key is `task_key`, and the value is the name
            assigned to the dependent task. This field is required when a job consists
            of more than one task.
        - libraries: An optional list of libraries to be installed on the cluster that
            executes the task. The default value is an empty list.
    :type tasks: dict
    :param tags: (templated) A map of tags associated with the job. These are forwarded
        to the cluster, as cluster tags for jobs clusters, and are subject to the same
        limitations as cluster tags. A maximum of 25 tags can be added to the job.
    :type tags: dict
    :param databricks_conn_id: The name of the Airflow connection to use.
        By default and in the common case this will be ``databricks_default``. To use
        token based authentication, provide the key ``token`` in the extra field for
        the connection.
    :type databricks_conn_id: string
    :param libraries: (templated) A JSON object list containing the libraries to be
        used within the tasks of the job.
        e.g.: libraries = [{
            "whl": "s3://BUCKET/CUSTOM.WHL"
        },
        {
            "jar": "s3://BUCKET/CUSTOM.JAR"
        }]
    :type libraries: list
    :param access_control_list: A JSON object list containing permission parameters
        which will be applied for jobs and clusters. When not set the default
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
    :param polling_period_seconds: Controls the rate which the task polls for the
        result each request made. When not set the default `API_POLLING_PERIOD_SECONDS`
        value (10 seconds) will be used as the waiting time between any recurrent
        requests inside the operator.
    :type polling_period_seconds: int
    :param retries: the number of Airflow task retries that should be performed before
        failing the task. When not set the default `TASK_RETRIES` value (3) will be
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

    JOB_CLUSTER_TASK_OPERATOR_TYPE = "QuintoAndarDatabricksCheckJobTaskOperator"

    template_fields = ("cluster_configuration", "tasks", "tags", "libraries")
    ui_color = "#FF3621"
    ui_fgcolor = "#fff"

    def __init__(
        self,
        cluster_configuration,
        tasks=None,
        tags=None,
        libraries=None,
        access_control_list=QuintoAndarDatabricksBaseOperator.CLUSTER_DEFAULT_PERMISSIONS,
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
        Creates a new ``QuintoAndarDatabricksExecuteJobClusterOperator``.
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
        self.cluster_configuration = cluster_configuration
        self.tasks = tasks or {}
        self.tags = tags or {}
        self.libraries = libraries or []
        self.access_control_list = access_control_list
        self.polling_period_seconds = polling_period_seconds
        self.databricks_conn_id = databricks_conn_id
        self.job_settings = {}
        self.job_id = None
        self.run_id = None
        self.run_page_url = None
        self.cluster_ids = []

    def pre_execute(self, context):
        """
        Sets the job_settings content:

        1. Removes autotermination_minutes cluster configuration;
        2. Defines the cluster name;
        3. Retrieves tags from cluster configurations;
        4. Generate job tasks from Airflow DAG tasks;
        5. Define job cluster specs from cluster configurations;
        6. Define job access control list;
        7. If exists, retrieves `job_id` from XCom.
        """
        # Work on a rendered copy so pre_execute is idempotent and any
        # Jinja templates (e.g. {{ dag.dag_id }} in custom_tags) are resolved.
        cluster_config = self.render_template(dict(self.cluster_configuration), context)

        autotermination = cluster_config.pop("autotermination_minutes", None)
        if autotermination:
            self.log.info(
                f"Provided autotermination limit of '{autotermination}' "
                "will be ignored for this job cluster."
            )
        cluster_name = (
            cluster_config.pop(
                "cluster_name",
                "{dag_id}_{run_id}".format(
                    dag_id=self.dag_id, run_id=context["run_id"]
                ),
            )
            .replace(".", "-")
            .replace(":", "")
            .replace("+", "_")
            .replace("_triggered", "")
        )
        execute_job_cluster_task_id = re.search(r"\d+", self.task_id)
        if execute_job_cluster_task_id:
            cluster_name = f"{cluster_name}{execute_job_cluster_task_id.group()}"
        self.job_settings["name"] = cluster_name
        self.job_settings["tags"] = self.render_template(
            self.tags or cluster_config.get("custom_tags", []),
            context,
        )
        self.job_settings["tasks"] = self.tasks or self._generate_job_tasks_from_dag(
            context, cluster_name, self.libraries
        )
        self.job_settings["job_clusters"] = {
            "job_cluster_key": cluster_name,
            "new_cluster": cluster_config,
        }
        self.job_settings["access_control_list"] = self.access_control_list
        self.job_settings = self._deep_string_coerce(self.job_settings)

        jobs_list = self.databricks_hook.list_jobs(name=cluster_name)
        if jobs_list:
            self.job_id = jobs_list[0]["job_id"]
            active_runs_list = self.databricks_hook.list_job_runs(
                self.job_id, active_only=True
            )
            if active_runs_list:
                self.run_id = active_runs_list[0]["run_id"]
                self.run_page_url = self.databricks_hook.generate_run_page_url(
                    self.job_id, self.run_id
                )

    def execute(self, context):
        """
        Performs main requests for a Job execution:

        1. Overwrites or creates a new Databricks job;
        2. Creates a new job run from the created/overwritten job;
        3. Gets the `cluster_ids` parameter from the tasks of the newly job run;
        4. Checks if the cluster is up and running.
        """
        execution_timeout = context["task"].execution_timeout
        start_date = context["ti"].start_date

        if self.job_id:
            self.log.info(
                f"Retrieved Databricks job ID '{self.job_id}' from Databricks Jobs list"
            )
            self.databricks_hook.reset_job(self.job_id, self.job_settings)
        else:
            self.job_id = self.databricks_hook.create_job(self.job_settings)
            self.xcom_push(
                context,
                key=self.XCOM_JOB_ID_KEY.format(
                    execute_job_cluster_task_id=self.task_id
                ),
                value=self.job_id,
            )

        if self.run_id:
            self.log.info(
                f"Databricks job ID '{self.job_id}' already has an active run ID "
                f"'{self.run_id}'. Proceeding with it."
            )
        else:
            self.run_id = self.databricks_hook.run_job_now(self.job_id)
            self.run_page_url = self.databricks_hook.generate_run_page_url(
                self.job_id, self.run_id
            )

        self.xcom_push(context, key=self.XCOM_RUN_PAGE_URL_KEY, value=self.run_page_url)
        self.xcom_push(
            context,
            key=self.XCOM_RUN_ID_KEY.format(execute_job_cluster_task_id=self.task_id),
            value=self.run_id,
        )

        while not self.cluster_ids:
            self._log_timeout_remaining(start_date, execution_timeout)
            job_run_state = self.databricks_hook.get_job_run_state(
                self.run_id, version=JOBS_API_VERSION
            )
            job_run_state.raise_for_state()
            self.cluster_ids = self.databricks_hook.get_job_run_cluster_ids(
                self.run_id, version=JOBS_API_VERSION
            )
            self._wait_polling_period(self.polling_period_seconds)
        self.xcom_push(context, key=self.XCOM_CLUSTER_ID_KEY, value=self.cluster_ids)

        self._monitor_clusters_state(
            self.databricks_hook,
            self.cluster_ids,
            start_date,
            execution_timeout,
            self.polling_period_seconds,
        )

    def post_execute(self, context, result):
        """
        Verifies if libraries were properly installed in job cluster.
        """
        execution_timeout = context["task"].execution_timeout
        start_date = context["ti"].start_date

        self._monitor_libraries_installation(
            self.databricks_hook,
            self.cluster_ids,
            start_date,
            execution_timeout,
            self.polling_period_seconds,
        )

    def on_kill(self):
        if self.cluster_ids:
            for cluster_id in self.cluster_ids:
                self._terminate_running_cluster(self.databricks_hook, cluster_id)
        else:
            self.log.warn("No Cluster IDs were found to be terminated.")

    def _generate_job_tasks_from_dag(self, context, cluster_name, libraries):
        """
        Generates a list with all tasks by exploring through the DAG vertexes and searching
        for specific type of Airflow tasks to link them as dependencies for Databricks.

        :param context: Airflow context dict
        :type context: dict
        :param cluster_name: name of the cluster added into job cluster request, to be
            attached to the tasks as the cluster where they will run.
        :type cluster_name: str
        :param libraries: A JSON object list containing the libraries to be used within the
            tasks of the job.
        :type libraries: list
        """
        job_tasks = []
        template_context = context["ti"].get_template_context()
        tasks = self._get_dag_tasks_downstream()
        for airflow_task in tasks:
            if issubclass(
                airflow_task.__class__, QuintoAndarDatabricksCheckJobTaskOperator
            ):
                depends_on = self._get_airflow_job_cluster_task_deps(airflow_task)
                rendered_json = self.render_template(
                    airflow_task.json, template_context
                )
                job_task = {
                    "task_key": airflow_task.task_id,
                    "depends_on": depends_on,
                    "job_cluster_key": cluster_name,
                    "libraries": libraries,
                    "timeout_seconds": airflow_task.execution_timeout.total_seconds(),
                    **rendered_json,
                }
                job_tasks.append(job_task)
        if not job_tasks:
            self.log.warn(
                f"No tasks were found in the DAG using '{self.JOB_CLUSTER_TASK_OPERATOR_TYPE}' class."
            )
        return job_tasks

    def _get_airflow_job_cluster_task_deps(self, airflow_task):
        """
        Checks if the provided Airflow task is of the required type. Otherwise,
        performs a search over its upstream dependencies using recursion, until the first
        of two option occurs: finds a `QuintoAndarDatabricksCheckJobTaskOperator` task or
        there are no more upstream dependencies.

        :param airflow_task: Airflow task object
        :type airflow_task: Operator
        """
        depends_on = []
        for upstream_task in airflow_task.upstream_list:
            if issubclass(
                upstream_task.__class__, QuintoAndarDatabricksCheckJobTaskOperator
            ):
                depends_on.append({"task_key": upstream_task.task_id})
            else:
                upstream_dep_task_ids = self._get_airflow_job_cluster_task_deps(
                    upstream_task
                )
                depends_on.extend(upstream_dep_task_ids)
        return depends_on

    def _get_dag_tasks_downstream(self, task=None, downstream_tasks: set = None) -> set:
        """
        Get all downstream tasks from a given task.

        :param task: Airflow task object
        :type task: Operator
        :param downstream_tasks: Set of downstream tasks
        :type downstream_tasks: set
        """
        task = task or self
        if not downstream_tasks:
            downstream_tasks = set()

        for downstream_task in task.downstream_list:
            downstream_tasks.add(downstream_task)
            self._get_dag_tasks_downstream(downstream_task, downstream_tasks)
        return downstream_tasks
