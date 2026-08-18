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


class QuintoAndarDatabricksCreateClusterOperator(QuintoAndarDatabricksBaseOperator):
    """
    Creates a Databricks Spark cluster, installing specific libraries and applying
    specific Access Control Lists onto it.

    Docs:
    - [Databricks API 2.0: Clusters create](https://docs.databricks.com/api/latest/clusters.html#create)
    - [Databricks API 2.0: Libraries install](https://docs.databricks.com/api/latest/libraries.html#install)

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
        which will be applied onto the cluster. When not set the default
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

    template_fields = ("cluster_configuration", "libraries")
    ui_color = "#FF3621"
    ui_fgcolor = "#fff"

    def __init__(
        self,
        cluster_configuration,
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
        Creates a new ``QuintoAndarDatabricksCreateClusterOperator``.
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
        self.libraries = libraries or []
        self.polling_period_seconds = polling_period_seconds
        self.cluster_configuration = cluster_configuration
        self.access_control_list = access_control_list
        self.databricks_conn_id = databricks_conn_id
        self.cluster_id = None
        self.cluster_page_url = None

    def pre_execute(self, context):
        """
        Coerces the content of the cluster configuration string.
        """
        self.cluster_configuration = self._deep_string_coerce(
            self.cluster_configuration
        )

    def execute(self, context):
        """
        Performs main requests for the cluster creation.

        1. Sends the creation request;
        2. Pushes the `cluster_id` into an XCom;
        3. Monitors the cluster until it's up an running;
        """
        execution_timeout = context["task"].execution_timeout
        start_date = context["ti"].start_date

        self._log_timeout_remaining(start_date, execution_timeout)
        self.cluster_id = self.databricks_hook.create_cluster(
            self.cluster_configuration
        )
        self.cluster_page_url = self.databricks_hook.generate_cluster_page_url(
            self.cluster_id
        )
        self.xcom_push(
            context, key=self.XCOM_CLUSTER_PAGE_URL_KEY, value=self.cluster_page_url
        )
        self.xcom_push(context, key=self.XCOM_CLUSTER_ID_KEY, value=self.cluster_id)
        self._monitor_clusters_state(
            self.databricks_hook,
            [self.cluster_id],
            start_date,
            execution_timeout,
            self.polling_period_seconds,
        )

    def post_execute(self, context, result):
        """
        1. Grants permissions for the cluster to the provided ACL;
        2. Verifies if libraries were properly installed in the cluster.
        """
        execution_timeout = context["task"].execution_timeout
        start_date = context["ti"].start_date

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

    def on_kill(self):
        """
        Forces the termination of the created rum, when it exists.
        """
        if self.cluster_id:
            self._terminate_running_cluster(self.databricks_hook, self.cluster_id)
        else:
            self.log.warn("No Cluster ID was found to be terminated.")
