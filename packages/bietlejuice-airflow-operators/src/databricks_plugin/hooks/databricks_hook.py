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
import time
from datetime import datetime, timezone

from airflow import __version__
from airflow.hooks.base_hook import BaseHook
from airflow.utils.log.logging_mixin import LoggingMixin
from databricks_cli.clusters.api import ClusterApi
from databricks_cli.jobs.api import JobsApi
from databricks_cli.libraries.api import LibrariesApi
from databricks_cli.sdk.api_client import ApiClient
from databricks_cli.sdk.version import API_VERSION, API_VERSIONS
from requests.exceptions import HTTPError

from databricks_plugin.states.cluster_state import ClusterState
from databricks_plugin.states.errors import DatabricksNotFoundError
from databricks_plugin.states.library_status import LibraryStatus
from databricks_plugin.states.run_state import RunState

JOBS_API_VERSION = "2.1"
USER_AGENT_HEADER = f"airflow-{__version__}"
API_ENTITY_TYPES = [
    "clusters",
    "instance-pools",
    "jobs",
    "pipelines",
    "notebooks",
    "directories",
    "experiments",
    "registered-models",
    "repos",
]


class QuintoAndarDatabricksHook(BaseHook, LoggingMixin):
    """
    Interacts with Databricks, using the databricks_cli library
    """

    def __init__(
        self,
        databricks_conn_id="databricks_default",
        api_version=API_VERSION,
        jobs_api_version=JOBS_API_VERSION,
    ):
        """
        :param databricks_conn_id: The name of the databricks connection to use.
            Defaults to `databricks_default`.
        :type databricks_conn_id: string
        :param api_version: Databricks API version to be used on clients.
            Defaults to 2.0.
        :type api_version: str or integer
        :param jobs_api_version: Databricks Jobs API version to be used on jobs clients.
            Defaults to 2.1.
        :type jobs_api_version: str or integer
        """
        self.api_version = api_version
        self.jobs_api_version = jobs_api_version
        self.host, auth = self._get_databricks_conn_data(databricks_conn_id)
        self.client = ApiClient(
            host=self.host,
            api_version=self.api_version,
            jobs_api_version=self.jobs_api_version,
            command_name=USER_AGENT_HEADER,
            **auth,
        )
        self.clusters_client = ClusterApi(self.client)
        self.libraries_client = LibrariesApi(self.client)
        self.jobs_client = JobsApi(self.client)

    @property
    def api_version(self):
        return self._api_version

    @api_version.setter
    def api_version(self, api_version):
        if api_version not in API_VERSIONS:
            raise ValueError(
                "API version must be one of the "
                f"available versions: {str(API_VERSIONS)}"
            )
        self._api_version = api_version

    @property
    def jobs_api_version(self):
        return self._jobs_api_version

    @jobs_api_version.setter
    def jobs_api_version(self, jobs_api_version):
        if jobs_api_version not in API_VERSIONS:
            raise ValueError(
                "Jobs API version must be one of the "
                f"available versions: {str(API_VERSIONS)}"
            )
        self._jobs_api_version = jobs_api_version

    def _get_databricks_conn_data(self, databricks_conn_id):
        """
        Returns connection data from a Databricks Airflow connection, retrieved from
        the provided ID.

        :param databricks_conn_id: Databricks Airflow connection ID
        :type cluster_configuration: string
        :rtype: tuple(string, dict)
        """
        databricks_conn = self.get_connection(databricks_conn_id)
        host = databricks_conn.host
        if "token" in databricks_conn.extra_dejson:
            self.log.info("Using token authentication.")
            auth = {"token": databricks_conn.extra_dejson["token"]}
        else:
            self.log.info("Using basic USER and LOGIN authentication.")
            auth = {
                "login": databricks_conn.login,
                "password": databricks_conn.password,
            }
        return (host, auth)

    def _retry_on_temporary_error(
        self, func, *args, max_retries=3, base_delay=1, **kwargs
    ):
        """
        Retries a function call when encountering temporary HTTP 500 errors with
        TEMPORARILY_UNAVAILABLE error code from Databricks API.

        :param func: The function to retry
        :type func: callable
        :param max_retries: Maximum number of retry attempts. Defaults to 3.
        :type max_retries: int
        :param base_delay: Base delay in seconds for exponential backoff. Defaults to 1.
        :type base_delay: float
        :param args: Positional arguments to pass to the function
        :param kwargs: Keyword arguments to pass to the function
        :rtype: The return value of the function
        """
        last_exception = None
        for attempt in range(max_retries):
            try:
                return func(*args, **kwargs)
            except HTTPError as ex:
                # Check if it's a 500 error with TEMPORARILY_UNAVAILABLE
                should_retry = False
                if hasattr(ex, "response") and ex.response is not None:
                    if ex.response.status_code == 500:
                        try:
                            error_response = ex.response.json()
                            error_code = error_response.get("error_code")
                            if error_code == "TEMPORARILY_UNAVAILABLE":
                                should_retry = True
                        except (ValueError, AttributeError, KeyError, TypeError):
                            # If we can't parse the error response as JSON, check error message
                            error_message = str(ex.args[0]) if ex.args else ""
                            if (
                                "TEMPORARILY_UNAVAILABLE" in error_message
                                or "temporarily unavailable" in error_message.lower()
                            ):
                                should_retry = True

                if should_retry:
                    if attempt < max_retries - 1:
                        delay = base_delay * (2**attempt)
                        self.log.warning(
                            f"Temporary API error (attempt {attempt + 1}/{max_retries}): "
                            f"TEMPORARILY_UNAVAILABLE. Retrying in {delay} seconds..."
                        )
                        time.sleep(delay)
                        last_exception = ex
                        continue
                    else:
                        # Last attempt failed, raise the exception
                        self.log.error(
                            f"Failed after {max_retries} retry attempts due to temporary API unavailability."
                        )
                        raise

                # If it's not a temporary error, re-raise immediately
                raise
            except Exception:
                # For non-HTTP errors, don't retry
                raise

        # If we've exhausted all retries, raise the last exception
        if last_exception:
            self.log.error(
                f"Failed after {max_retries} retry attempts due to temporary API unavailability."
            )
            raise last_exception

    def _get_evaluated_dict_from_list(
        self,
        list_of_dicts: list,
        ordering_key: str,
        evaluation_callable: callable = None,
        evaluation_args: list = None,
        latest: bool = True,
    ):
        """
        Performs a search over a provided list for the first (or the last) dict that
        evaluates True to the condition provided within `evaluation_callable`, with
        the list being ordered by a given `ordering_key`. The dict may be the latest
        or the first of the resulting dicts, according to the `latest` arg value.

        :param list_of_dicts: a list containing the dicts to be evaluated
        :type list_of_dicts: list[dict]
        :param ordering_key: the key to be used to order each dict in the list.
        :type ordering_key: str
        :param evaluation_callable: a Python callable that must return a boolean
            used as condition to filter the dicts from the list.
            The callable by default must receive the `idx` and `elem` arguments,
            as the list's element and index, respectively.
            Defaults to `None`.
        :type evaluation_callable: callable
        :param evaluation_args: extra positional args to be provided to the evaluation
            callable. They are provided after the first two (`idx` and `elem`) args.
            Defaults to `None`.
        :type evaluation_args: list,
        :param latest: Whether to return the latest dict retrieved from evaluation.
            If `False`, returns the first dict. Defaults to `True`.
        :type latest: bool
        :rtype: dict
        """
        evaluation_function = max if latest else min
        evaluation_callable = evaluation_callable or (lambda *_: True)
        evaluation_args = evaluation_args or []

        elem_ids = {
            idx: elem[ordering_key]
            for idx, elem in enumerate(list_of_dicts)
            if evaluation_callable(idx, elem, *evaluation_args)
        }
        return (
            list_of_dicts[evaluation_function(elem_ids, key=elem_ids.get)]
            if elem_ids
            else {}
        )

    def create_cluster(self, cluster_configuration):
        """
        Sends a cluster creation request to Databricks.

        :param cluster_configuration: JSON dict with cluster configurations to be sent
        :type cluster_configuration: dict
        :rtype: str
        """
        self.log.info("Creating Databricks cluster...")
        cluster_id = self.clusters_client.create_cluster(cluster_configuration).get(
            "cluster_id"
        )
        if cluster_id:
            self.log.info(f"Cluster created with ID: {cluster_id}")
        else:
            self.log.warn("No cluster ID returned from request.")
        return cluster_id

    def start_cluster(self, cluster_id):
        """
        Starts a terminated cluster given its ID.
        This is similar to createCluster, except:

        - The terminated cluster ID and attributes are preserved.
        - The cluster restarts with the last specified cluster size.
            If the terminated cluster is an autoscaling cluster, the
            cluster restarts with the minimum number of nodes.
        - If the cluster is in the RESTARTING state, a 400 error is returned.
        - You cannot restart a cluster launched to run a job.

        :param cluster_id: The cluster to be started. This field is required.
        :type cluster_id: str
        :rtype: None
        """
        self.log.info(f"Starting cluster '{cluster_id}'...")
        self.clusters_client.start_cluster(cluster_id=cluster_id)

    def restart_cluster(self, cluster_id):
        """
        Restart a cluster given its ID.
        The cluster must be in the RUNNING state.

        :param cluster_id: The cluster to be restarted. This field is required.
        :type cluster_id: str
        :rtype: None
        """
        self.log.info(f"Restarting cluster '{cluster_id}'...")
        self.clusters_client.restart_cluster(cluster_id=cluster_id)

    def terminate_cluster(self, cluster_id):
        """
        Sends a cluster termination request to Databricks.

        :param cluster_id: ID of the cluster that will be terminated
        :type cluster_id: str
        :rtype: None
        """
        self.log.info(f"Terminating cluster '{cluster_id}'...")
        self.clusters_client.delete_cluster(cluster_id)

    def get_cluster_state(self, cluster_id):
        """
        Retrieves the state of a cluster given its identifier.
        Clusters can be described while they are running or up to 30 days after
        they are terminated.
        Check ["Clusters API:get" docs](https://docs.databricks.com/dev-tools/api/latest/clusters.html#get).

        :param cluster_id: The cluster about which to retrieve state information.
            This field is required.
        :type cluster_id: string
        :rtype: :class:ClusterState
        """
        self.log.info(f"Retrieving state for cluster '{cluster_id}'...")
        response = self._retry_on_temporary_error(
            self.clusters_client.get_cluster, cluster_id
        )
        state = response["state"]
        state_message = response["state_message"]
        cluster_state = ClusterState(state, state_message)
        self.log.info(
            f"Cluster '{cluster_id}' in state '{cluster_state.state}' "
            f"with message: {cluster_state.state_message}"
        )
        return cluster_state

    def generate_cluster_page_url(self, cluster_id: str):
        """
        Generates a URL to the detail page of a cluster, using the cluster ID provided.

        :param cluster_id: The canonical identifier of the cluster used to generate the cluster page URL.
            This field is required.
        :type cluster_id: string
        :rtype: string
        """
        cluster_page_url = f"{self.host}/#setting/clusters/{cluster_id}"
        if cluster_id:
            self.log.info(f"Cluster details: {cluster_page_url}")
        else:
            self.log.error(
                "Cluster page URL requires a non empty value for 'cluster_id'."
            )
        return cluster_page_url

    def list_jobs(
        self, name: str = None, expand_tasks: bool = False, version=JOBS_API_VERSION
    ):
        """
        Retrieves a list of all Databricks jobs.
        Check ["List jobs" docs](https://docs.databricks.com/api/workspace/jobs/list).

        :param name: A filter on the list based on the exact (case insensitive) job
            name. Defaults to `None`.
        :type name: str
        :param expand_tasks: Whether to include task and cluster details in the
            response. Defaults to `False`.
        :type expand_tasks: bool
        :param version: Databricks API version to be used for this request.
            Defaults to `2.1`.
        :type version: str or float
        :rtype: list
        """
        self.log.info("Retrieving Databricks jobs list...")

        has_more = True
        limit = 100
        page_token = None
        jobs_list = []

        while has_more:
            _data = {}
            _data["expand_tasks"] = expand_tasks
            _data["limit"] = limit
            if name:
                _data["name"] = name
            if page_token:
                _data["page_token"] = page_token
            response = self.jobs_client.client.client.perform_query(
                "GET", "/jobs/list", data=_data, version=version
            )
            jobs_list += response.get("jobs", [])
            has_more = response.get("has_more", False)
            page_token = response.get("next_page_token")
        self.log.info(f"Quantity of jobs returned: {len(jobs_list)}")
        return jobs_list

    def list_job_runs(
        self, job_id: int, active_only: bool = False, version=JOBS_API_VERSION
    ):
        """
        Retrieves a list of all runs for a specific Databricks job.
        Check ["List job runs" docs](https://docs.databricks.com/api/workspace/jobs/listruns).

        :param job_id: The canonical identifier of the job for which to list runs.
            This field is required.
        :type job_id: integer
        :param active_only: Whether to only return active runs. Defaults to `False`.
        :type active_only: bool
        :param version: Databricks API version to be used for this request.
            Defaults to `2.1`.
        :type version: str or float
        :rtype: list
        """
        self.log.info(f"Retrieving runs list for Databricks job '{job_id}'...")

        has_more = True
        limit = 25
        offset = 0
        job_runs_list = []

        while has_more:
            _data = {"job_id": job_id, "limit": limit, "offset": offset}
            if active_only:
                _data["active_only"] = active_only
            response = self.jobs_client.client.client.perform_query(
                "GET", "/jobs/runs/list", data=_data, version=version
            )
            job_runs_list += response.get("runs", [])
            has_more = response.get("has_more", False)
            offset += limit
        self.log.info(
            f"Quantity of runs returned for job '{job_id}': {len(job_runs_list)}"
        )
        return job_runs_list

    def create_job(self, job_settings: dict):
        """
        Creates a new Databricks job.
        Check ["Create a new job" docs](https://docs.databricks.com/dev-tools/api/latest/jobs.html#operation/JobsCreate).

        :param job_settings: JSON dict with job settings to be sent
        :type job_settings: dict
        :rtype: integer
        """
        self.log.info("Creating Databricks job...")
        job_id = self.jobs_client.create_job(json=job_settings).get("job_id")
        self.log.info(f"Job created with ID: {job_id}")
        return job_id

    def reset_job(self, job_id: int, job_settings: dict):
        """
        Overwrites all the settings for a specific job.
        Check ["Overwrites all settings for a job" docs](https://docs.databricks.com/dev-tools/api/latest/jobs.html#operation/JobsReset).

        :param job_id: The canonical identifier of the job to reset.
            This field is required.
        :type job_id: integer
        :param job_settings: JSON dict with job settings to be sent
        :type job_settings: dict
        :rtype: None
        """
        self.log.info(f"Updating Databricks job '{job_id}' with new settings...")
        self.jobs_client.client.reset_job(job_id=job_id, new_settings=job_settings)
        self.log.info(f"Job '{job_id}' updated.")

    def delete_job(self, job_id: int):
        """
        Deletes an existing Databricks job.
        Check ["Delete a job" docs](https://docs.databricks.com/api/workspace/jobs/delete).

        :param job_id: The canonical identifier of the job to delete.
            This field is required.
        :type job_id: int
        :rtype: None
        """
        self.log.info(f"Deleting Databricks job '{job_id}'...")
        self.jobs_client.delete_job(job_id=job_id)
        self.log.info(f"Job '{job_id}' deleted.")

    def repair_job_run(
        self,
        run_id: int,
        latest_repair_id: int = None,
        rerun_all_failed_tasks: bool = False,
        rerun_tasks: list = None,
        tasks_params: dict = None,
        version=JOBS_API_VERSION,
    ):
        """
        Re-runs one or more tasks. Tasks are re-run as part of the original job run,
        use the current job and task settings, and can be viewed in the history for
        the original job run. Each re-run creates a new job cluster.
        Check ["Repair a job run" docs](https://docs.databricks.com/dev-tools/api/latest/jobs.html#operation/JobsRunsRepair).

        :param run_id: The canonical identifier of the job run for which to send the
            repair. The run must not be in progress. This field is required.
        :type run_id: integer
        :param latest_repair_id: The ID of the latest repair. This parameter is not
            required when repairing a run for the first time, but must be provided on
            subsequent requests to repair the same run. Defaults to `None`.
        :type latest_repair_id: integer
        :param rerun_all_failed_tasks: If true, repairs all failed tasks, including
            tasks with status `TERMINATED`, `SKIPPED` and `INTERNAL_ERROR`. Only one of
            `rerun_tasks` or `rerun_all_failed_tasks` can be used. Defaults to `False`.
        :type rerun_all_failed_tasks: boolean
        :param rerun_tasks: The task keys of the task runs to repair. Only one of
            `rerun_tasks` or `rerun_all_failed_tasks` can be used. Defaults to `None`.
        :type rerun_tasks: list[str]
        :param tasks_params: A dict with definitions of new parameters to be set for
            all job tasks of the provided types. Defaults to `None`. The dict keys
            must be a combination of one or many of the following task types:
            - jar_params
            - notebook_params
            - python_params
            - spark_submit_params
            - python_named_params
            - pipeline_params
            - dbt_commands

        :type tasks_params: dict
        :param version: Databricks API version to be used for this request.
            Defaults to `2.1`.
        :type version: str or float
        :rtype: integer
        """
        self.log.info(f"Repairing Databricks job run '{run_id}'...")
        if tasks_params:
            self.log.warn(
                "Repaired tasks of the following types will have their parameters"
                f" overriden by their following respective parameters: {tasks_params}"
            )
        tasks_params = tasks_params or {}
        repair_id = self.jobs_client.client.repair(
            run_id=run_id,
            latest_repair_id=latest_repair_id,
            rerun_all_failed_tasks=rerun_all_failed_tasks,
            rerun_tasks=rerun_tasks,
            version=version,
            **tasks_params,
        ).get("repair_id")
        self.log.info(f"Job repair running with repair ID: {repair_id}")
        return repair_id

    def get_repair_id(self, run_id: int, latest: bool = True, version=JOBS_API_VERSION):
        """
        Retrieves the repair ID of a job run with the provided `run_id`, or `None` if
        no repairs are found. For default, returns the ID of the latest repair in order
        of start time.
        Check ["Get a single job run" docs](https://docs.databricks.com/dev-tools/api/latest/jobs.html#operation/JobsRunsGet).

        :param run_id: The canonical identifier of the job run for which to
            retrieve the latest repair ID. This field is required.
        :type run_id: integer
        :param latest: Whether to return the ID of the latest repair in time.
            If `False`, returns the repair ID. Defaults to `True`.
        :type latest: bool
        :param version: Databricks API version to be used for this request.
            Defaults to 2.0.
        :type version: str or float
        :rtype: integer or None
        """
        self.log.info(f"Retrieving repair ID of job run '{run_id}'...")
        job_run_metadata = self.get_job_run(
            run_id=run_id, include_history=True, version=version
        )
        repair_id = self._get_evaluated_dict_from_list(
            list_of_dicts=job_run_metadata["repair_history"],
            ordering_key="start_time",
            latest=latest,
        ).get("id")
        if repair_id:
            self.log.info(f"Job run '{run_id}' returned repair ID: {repair_id}")
        else:
            self.log.info(f"No repairs were found for job run '{run_id}'.")
        return repair_id

    def get_task_repair_state(
        self,
        run_id: int,
        task_run_id: int,
        latest: bool = True,
        version=JOBS_API_VERSION,
    ):
        """
        Retrieves the state of the repair run that contains a provided `task_run_id`.
        If the job run has not been repaired yet, returns the original run state.
        Raises an exception if no repair runs with the provided `task_run_id` are
        found, most probably due to a provided `task_run_id` that does not belong
        to the provided `run_id`.
        Check ["Get a single job run" docs](https://docs.databricks.com/dev-tools/api/latest/jobs.html#operation/JobsRunsGet).

        :param run_id: The canonical identifier of the job run for which to
            retrieve the state of the repair run. This field is required.
        :type run_id: integer
        :param task_run_id: The canonical identifier of the task run, used to retrieve
            the latest repair run that contains it. This field is required.
        :type task_run_id: integer
        :param latest: Whether to return the state of the latest repair in time.
            If `False`, returns the state of the latest repair. Defaults to `True`.
        :type latest: bool
        :param version: Databricks API version to be used for this request.
            Defaults to 2.0.
        :type version: str or float
        :rtype: :class:RunState
        """
        self.log.info(
            "Retrieving state of the {} repair with the task run ID '{}'...".format(
                "latest" if latest else "first", task_run_id
            )
        )
        job_run_metadata = self.get_job_run(
            run_id=run_id, include_history=True, version=version
        )
        job_run_repair = self._get_evaluated_dict_from_list(
            list_of_dicts=job_run_metadata["repair_history"],
            ordering_key="start_time",
            evaluation_callable=(
                lambda _, elem, task_run_id: task_run_id in elem["task_run_ids"]
            ),
            evaluation_args=[task_run_id],
            latest=latest,
        )
        if job_run_repair:
            repair_state = RunState(**job_run_repair["state"])
            self.log.info(
                "{} job run with ID '{}' in state '{}' ".format(
                    job_run_repair["type"],
                    job_run_repair.get("id", run_id),
                    repair_state.life_cycle_state,
                )
            )
            return repair_state
        raise DatabricksNotFoundError(
            f"Task run ID '{task_run_id}' was not found for job run '{run_id}'."
        )

    def submit_run(self, json: dict, idempotency_token=None, version=API_VERSION):
        """
        Submits a one-time run and returns the `run_id` of the triggered run.
        Allows the submittion of a workload directly without creating a job.
        Check ["Runs submit" docs](https://docs.databricks.com/dev-tools/api/2.0/jobs.html#runs-submit).

        :param json: A JSON object containing API parameters which will be passed
            directly to the endpoint.
        :type json: dict
        :param idempotency_token: An optional token to guarantee the idempotency of job
            run requests. If a run with the provided token already exists, the request
            does not create a new run but returns the ID of the existing run instead.
            If a run with the provided token is deleted, an error is returned.
            If you specify the idempotency token, upon failure you can retry until the
            request succeeds. Databricks guarantees that exactly one run is launched
            with that idempotency token.
            This token must have at most 64 characters.
            For more information, see [How to ensure idempotency for jobs](https://kb.databricks.com/jobs/jobs-idempotency.html).
        :type idempotency_token: str
        :param version: Databricks API version to be used for this request. Defaults to 2.0.
        :type version: str or float
        :rtype: integer
        """
        self.log.info(
            "Submitting Databricks run '{}'...".format(json.get("run_name", "Unnamed"))
        )
        run_id = self.jobs_client.client.submit_run(
            **json, idempotency_token=idempotency_token, version=version
        ).get("run_id")
        self.log.info(f"Run submitted with run ID: {run_id}")
        return run_id

    def run_job_now(self, job_id: int, idempotency_token=None):
        """
        Runs a job and return the `run_id` of the triggered run.
        Check ["Trigger a new job run" docs](https://docs.databricks.com/dev-tools/api/latest/jobs.html#operation/JobsRunNow).

        :param job_id: The ID of the job to be executed
        :type job_id: integer
        :param idempotency_token: An optional token to guarantee the idempotency of job
            run requests. If a run with the provided token already exists, the request
            does not create a new run but returns the ID of the existing run instead.
            If a run with the provided token is deleted, an error is returned.
            If you specify the idempotency token, upon failure you can retry until the
            request succeeds. Databricks guarantees that exactly one run is launched
            with that idempotency token.
            This token must have at most 64 characters.
            For more information, see [How to ensure idempotency for jobs](https://kb.databricks.com/jobs/jobs-idempotency.html).
        :type idempotency_token: str
        :rtype: integer
        """
        self.log.info(f"Triggering Databricks job '{job_id}'...")
        run_id = self.jobs_client.client.run_now(
            job_id=job_id, idempotency_token=idempotency_token
        ).get("run_id")
        self.log.info(f"Job '{job_id}' triggered with run ID: {run_id}")
        return run_id

    def get_job_run(
        self, run_id: int, include_history: bool = False, version=API_VERSION
    ):
        """
        Retrieves the metadata of a job run.
        Check ["Get a single job run" docs](https://docs.databricks.com/dev-tools/api/latest/jobs.html#operation/JobsRunsGet).

        :param run_id: The canonical identifier of the run for which to retrieve the metadata. This field is required.
        :type run_id: integer
        :param include_history: Whether to include the repair history in the response.
        :type include_history: bool
        :param version: Databricks API version to be used for this request. Defaults to 2.0.
        :type version: str or float
        :rtype: dict
        """
        self.log.debug(f"Retrieving metadata from Databricks job run '{run_id}'...")
        include_history = None if version == API_VERSION else include_history
        job_run_metadata = self._retry_on_temporary_error(
            self.jobs_client.client.get_run,
            run_id=run_id,
            include_history=include_history,
            version=version,
        )
        return job_run_metadata

    def get_job_run_logs(self, run_id: int, version=API_VERSION):
        """
        Retrieves the output logs of a job run.
        Check ["Get the output for a single run" docs](https://docs.databricks.com/dev-tools/api/latest/jobs.html#operation/JobsRunsGetOutput).

        :param run_id: The canonical identifier of the run for which to retrieve the output logs.
            This field is required.
        :type run_id: integer
        :param version: Databricks API version to be used for this request. Defaults to 2.0.
        :type version: str or float
        :rtype: str
        """
        self.log.info(f"Retrieving output logs from Databricks job run '{run_id}'...")
        job_run_output = self._retry_on_temporary_error(
            self.jobs_client.client.get_run_output, run_id=run_id, version=version
        )
        job_run_logs = job_run_output.get("logs", "")
        if job_run_output.get("logs_truncated"):
            job_run_logs = job_run_logs + "\n(Logs truncated)"
        if not job_run_logs:
            self.log.info(f"No logs were found in Databricks run '{run_id}'.")
        return job_run_logs

    def get_job_run_error_and_trace(self, run_id: int, version=API_VERSION):
        """
        Retrieves the error and its stack trace (if present) from the output of a single
        task run. Validates that the `run_id` parameter is valid and returns an HTTP
        status code 400 if the `run_id` parameter is invalid. Runs are automatically
        removed after 60 days.
        Returns a dict with two keys:
            - error: An error message indicating why a task failed or why output is not
                available. The message is unstructured, and its exact format is subject
                to change.
            - error_trace: If there was an error executing the run, this field contains
                any available stack traces.
        Check ["Get the output for a single run" docs](https://docs.databricks.com/dev-tools/api/latest/jobs.html#operation/JobsRunsGetOutput).


        :param run_id: The canonical identifier of the run for which to retrieve the metadata. This field is required.
        :type run_id: integer
        :param version: Databricks API version to be used for this request. Defaults to 2.0.
        :type version: str or float
        :rtype: dict
        """
        self.log.info(
            f"Retrieving error stack trace from Databricks job run '{run_id}'..."
        )
        job_run_output = self._retry_on_temporary_error(
            self.jobs_client.client.get_run_output, run_id=run_id, version=version
        )
        job_run_error = job_run_output.get("error")
        job_run_error_and_trace = {
            "error": job_run_error,
            "error_trace": job_run_output.get("error_trace"),
        }
        if job_run_error:
            self.log.error(f"Error found in Databricks run '{run_id}': {job_run_error}")
        else:
            self.log.info(f"No errors were found in Databricks run '{run_id}'.")
        return job_run_error_and_trace

    def get_job_task_attempt(
        self, run_id: int, task_key: str, latest: bool = True, version=API_VERSION
    ):
        """
        Retrieves the first or the lastest task attempt object of a job run.
        Check ["Get a single job run" docs](https://docs.databricks.com/dev-tools/api/latest/jobs.html#operation/JobsRunsGet).

        :param run_id: The canonical identifier of the run for which to retrieve the
            task's attempt object. This field is required.
        :type run_id: integer
        :param task_key: The unique name of the task for which to retrieve the task's
            attempt object. This field is required.
        :type task_key: str ^[\\w\\-]+$
        :param version: Databricks API version to be used for this request.
            Defaults to 2.0.
        :type version: str or float
        :param latest: Whether to return the latest task run attempt object in time.
            If `False`, returns the ID of the first task run attempt. Defaults to `True`.
        :type latest: bool
        :rtype: integer
        """
        self.log.info(
            "Retrieving {} attempt of task '{}'...".format(
                "latest" if latest else "first", task_key
            )
        )
        job_run_metadata = self.get_job_run(
            run_id=run_id, include_history=True, version=version
        )
        job_run_task = self._get_evaluated_dict_from_list(
            list_of_dicts=job_run_metadata["tasks"],
            ordering_key="attempt_number",
            evaluation_callable=(
                lambda _, elem, task_key: task_key == elem["task_key"]
            ),
            evaluation_args=[task_key],
            latest=latest,
        )
        if job_run_task:
            self.log.info(
                "Retrieved attempt {} of task '{}'...".format(
                    job_run_task["attempt_number"], task_key
                )
            )
            return job_run_task
        raise DatabricksNotFoundError(
            f"Task '{task_key}' was not found for job run '{run_id}'."
        )

    def get_job_run_task_run_id(
        self, run_id: int, task_key: str, latest: bool = True, version=API_VERSION
    ):
        """
        Retrieves the run ID of a task of a job run.
        Check ["Get a single job run" docs](https://docs.databricks.com/dev-tools/api/latest/jobs.html#operation/JobsRunsGet).

        :param run_id: The canonical identifier of the run for which to retrieve the
            task's run ID. This field is required.
        :type run_id: integer
        :param task_key: The unique name of the task for which to retrieve the run ID.
            This field is required.
        :type task_key: str ^[\\w\\-]+$
        :param latest: Whether to return the ID of the latest task run attempt in time.
            If `False`, returns the ID of the first task run attempt. Defaults to `True`.
        :type latest: bool
        :param version: Databricks API version to be used for this request.
            Defaults to 2.0.
        :type version: str or float
        :rtype: integer
        """
        self.log.info(
            f"Retrieving task run ID for task '{task_key}' of job run '{run_id}'..."
        )
        job_task_attempt = self.get_job_task_attempt(
            run_id=run_id, task_key=task_key, latest=latest, version=version
        )
        task_run_id = job_task_attempt["run_id"]
        self.log.info(
            f"Task '{task_key}' of job run '{run_id}' "
            f"returned task run ID: {task_run_id}"
        )
        return task_run_id

    def get_job_run_task_state(
        self, run_id: int, task_key: str, latest: bool = True, version=API_VERSION
    ):
        """
        Retrieves the state of a task of a job run.
        Check ["Get a single job run" docs](https://docs.databricks.com/dev-tools/api/latest/jobs.html#operation/JobsRunsGet).

        :param run_id: The canonical identifier of the run for which to retrieve the task's state.
            This field is required.
        :type run_id: integer
        :param task_key: The unique name of the task for which to retrieve the state. This field is required.
        :type task_key: str ^[\\w\\-]+$
        :param latest: Whether to return the state of the latest task run attempt in time.
            If `False`, returns the sate of the first task run attempt. Defaults to `True`.
        :type latest: bool
        :param version: Databricks API version to be used for this request. Defaults to 2.0.
        :type version: str or float
        :rtype: :class:RunState
        """
        self.log.info(f"Retrieving state of task '{task_key}' of job run '{run_id}'...")
        job_task_attempt = self.get_job_task_attempt(
            run_id=run_id, task_key=task_key, latest=latest, version=version
        )
        job_task_state = job_task_attempt["state"]
        self.log.info(
            "Task '{}' of job run '{}' in state: {}".format(
                task_key, run_id, job_task_state["life_cycle_state"]
            )
        )
        return RunState(**job_task_state)

    def get_job_run_state(self, run_id, version=API_VERSION):
        """
        Retrieves the state of a job run.
        Check ["Get a single job run" docs](https://docs.databricks.com/dev-tools/api/latest/jobs.html#operation/JobsRunsGet).

        :param run_id: The canonical identifier of the run for which to retrieve the state.
            This field is required.
        :type run_id: integer
        :param version: Databricks API version to be used for this request. Defaults to 2.0.
        :type version: str or float
        :rtype: :class:RunState
        """
        self.log.info(f"Retrieving state for job run '{run_id}'...")
        job_run_metadata = self.get_job_run(run_id=run_id, version=version)
        state = job_run_metadata["state"]["life_cycle_state"]
        self.log.info(f"Job run '{run_id}' in state: {state}")
        return RunState(**job_run_metadata["state"])

    def get_job_run_page_url(self, run_id: int, version=API_VERSION):
        """
        Retrieves the URL to the detail page of the job run.
        Check ["Get a single job run" docs](https://docs.databricks.com/dev-tools/api/latest/jobs.html#operation/JobsRunsGet).

        :param run_id: The canonical identifier of the run for which to retrieve the run page URL.
            This field is required.
        :type run_id: integer
        :param version: Databricks API version to be used for this request. Defaults to 2.0.
        :type version: str or float
        :rtype: string
        """
        job_run_metadata = self.get_job_run(run_id=run_id, version=version)
        run_page_url = job_run_metadata.get("run_page_url")
        if run_page_url:
            self.log.info(f"Job run details: {run_page_url}")
        else:
            self.log.info(f"Job run '{run_id}' returned no run page URL.")
        return run_page_url

    def generate_run_page_url(self, job_id: int, run_id: int):
        """
        Generates a URL to the detail page of a run, using job and run IDs provided.

        :param job_id: The canonical identifier of the job used to generate the run page URL.
            This field is required.
        :type job_id: integer
        :param job_id: The canonical identifier of the run for which to generate the run page URL.
            This field is required.
        :type run_id: integer
        :rtype: string
        """
        run_page_url = f"{self.host.rstrip('/')}/#job/{job_id}/run/{run_id}"
        if job_id and run_id:
            self.log.info(f"Run details: {run_page_url}")
        else:
            self.log.error(
                "Run page URL requires non empty values for 'job_id' and 'run_id'."
            )
        return run_page_url

    def get_job_run_cluster_ids(
        self, run_id: int, deduplicate=True, version=API_VERSION
    ):
        """
        Retrieves the cluster IDs of a job run, according to the format of the job (`MULTI_TASK`
        or `SINGLE_TASK`). For a `MULTI_TASK` job, all tasks' cluster IDs will be retrieved.
        Check ["Get a single job run" docs](https://docs.databricks.com/dev-tools/api/latest/jobs.html#operation/JobsRunsGet).

        :param run_id: The canonical identifier of the run for which to retrieve the cluster ID.
            This field is required.
        :type run_id: integer
        :param deduplicate: Whether to remove duplicated cluster IDs from the result.
            Defaults to True.
        :type deduplicate: bool
        :param version: Databricks API version to be used for this request. Defaults to 2.0.
        :type version: str or float
        :rtype: list[str]
        """
        job_run_metadata = self.get_job_run(run_id=run_id, version=version)
        job_run_format = job_run_metadata["format"]

        self.log.debug(f"Parsing {job_run_format} payload...")
        if job_run_format == "SINGLE_TASK":
            cluster_ids = [
                self.get_single_task_job_cluster_id(job_run_metadata=job_run_metadata)
            ]
        cluster_ids = self.get_multi_task_job_cluster_ids(
            job_run_metadata=job_run_metadata
        )
        if deduplicate:
            cluster_ids = list(set(cluster_ids))
        return cluster_ids

    def get_single_task_job_cluster_id(
        self,
        run_id: int = None,
        job_run_metadata: dict = None,
        version=API_VERSION,
        polling_period_seconds: int = None,
        start_date=datetime,
        execution_timeout=None,
    ):
        """
        Retrieves the cluster ID of SINGLE_TASK a job run. Optionally, it can poll for the
        cluster ID until it is available, with a given polling period and timeout.
        Check ["Get a single job run" docs](https://docs.databricks.com/dev-tools/api/latest/jobs.html#operation/JobsRunsGet).

        :param run_id: The canonical identifier of the run for which to retrieve the task's
            cluster ID. When provided, will be used on a `get_job_run` request to retrieve
            job run's metadata. Defaults to None.
        :type run_id: integer
        :param job_run_metadata: a dict containing the job run's metadata obtained from a
            `get_job_run` request. When provided, it used to retrieve job run's cluster ID.
        :type job_run_metadata: dict
        :param version: Databricks API version to be used for this request. Defaults to 2.0.
        :type version: str or float
        :param polling_period_seconds: The time in seconds to wait between retries when
            polling for the cluster ID. If set, the `start_date` and `execution_timeout`
            parameters must also be set. Defaults to None.
        :type polling_period_seconds: int
        :param start_date: The datetime object representing the start date of the polling
            period. If set, the `polling_period_seconds` and `execution_timeout` parameters
            must also be set. Defaults to None.
        :type start_date: datetime.datetime
        :param execution_timeout: Interval of time in seconds to wait for the cluster ID
            before timing out. If set, the `polling_period_seconds` and `start_date`
            parameters must also be set. Defaults to None.
        :rtype: string
        """
        self._verify_polling_parameters(
            polling_period_seconds, start_date, execution_timeout
        )

        now = datetime.now(timezone.utc)
        is_first_run = True
        cluster_id = None
        retry_until_timeout = polling_period_seconds is not None

        # Always run at least once. Continue (until timeout) only if cluster_id is not found and polling is enabled.
        while is_first_run or (
            cluster_id is None
            and retry_until_timeout
            and now < start_date + execution_timeout
        ):
            if run_id:
                job_run_metadata = self.get_job_run(run_id=run_id, version=version)
                run_id = job_run_metadata["run_id"]
            cluster_id = job_run_metadata.get("cluster_instance", {}).get("cluster_id")
            if cluster_id:
                self.log.info(f"Job run '{run_id}' returned cluster ID: {cluster_id}")
                return cluster_id

            is_first_run = False
            now = datetime.now(timezone.utc)
            if retry_until_timeout:
                self.log.info(f"Job run '{run_id}' returned no cluster ID. Retrying...")
                time.sleep(polling_period_seconds)

        self.log.info(f"Job run '{run_id}' returned no cluster ID.")
        return None

    def _verify_polling_parameters(
        self, polling_period_seconds, start_date, execution_timeout
    ):
        """Makes sure that, if one of the parameters are set, all the others are too."""

        if polling_period_seconds is not None and (
            start_date is None or execution_timeout is None
        ):
            raise ValueError(
                "If polling_period_seconds is set, start_date and execution_timeout must also be set."
            )
        if start_date is not None and (
            execution_timeout is None or polling_period_seconds is None
        ):
            raise ValueError(
                "If start_date is set, execution_timeout and polling_period_seconds must also be set."
            )
        if execution_timeout is not None and (
            start_date is None or polling_period_seconds is None
        ):
            raise ValueError(
                "If execution_timeout is set, start_date and polling_period_seconds must also be set."
            )

    def get_multi_task_job_cluster_ids(
        self, run_id: int = None, job_run_metadata: dict = None, version=API_VERSION
    ):
        """
        Retrieves all the cluster IDs of the tasks of a MULTI_TASK job run.
        Check ["Get a single job run" docs](https://docs.databricks.com/dev-tools/api/latest/jobs.html#operation/JobsRunsGet).

        :param run_id: The canonical identifier of the run for which to retrieve the task's
            cluster ID. When provided, will be used on a `get_job_run` request to retrieve
            job run's metadata. Defaults to None.
        :type run_id: integer
        :param job_run_metadata: a dict containing the job run's metadata obtained from a
            `get_job_run` request. When provided, it is looped upon to retrieve job run's
            first initial task. Defaults to None.
        :type job_run_metadata: dict
        :param version: Databricks API version to be used for this request. Defaults to 2.0.
        :type version: str or float
        :rtype: list[str]
        """
        if run_id:
            job_run_metadata = self.get_job_run(run_id=run_id, version=version)
        run_id = job_run_metadata["run_id"]

        cluster_ids = [
            job_run_task.get("cluster_instance", {}).get("cluster_id")
            for job_run_task in job_run_metadata.get("tasks", [])
            if job_run_task.get("cluster_instance", {}).get("cluster_id")
        ]
        if cluster_ids:
            self.log.info(
                "Job run '{}' returned cluster IDs: {}".format(
                    run_id, ",".join(cluster_ids)
                )
            )
        else:
            self.log.info(f"Job run '{run_id}' returned no cluster ID.")
        return cluster_ids

    def cancel_job_run(self, run_id, version=API_VERSION):
        """
        Cancels a job run. The run is cancelled asynchronously, so it may still be
        running when this request completes.
        Check ["Cancel a job run" docs](https://docs.databricks.com/dev-tools/api/latest/jobs.html#operation/JobsRunsCancel).

        :param run_id: The canonical identifier of the run. This field is required.
        :type run_id: integer
        :param version: Databricks API version to be used for this request.
            Defaults to 2.0.
        :type version: str or float
        :rtype: string
        """
        self.log.info(f"Cancelling job run '{run_id}'...")
        self.jobs_client.client.cancel_run(run_id=run_id, version=version)

    def install_libraries(self, cluster_id, libraries):
        """
        Installs libraries on a cluster.
        The installation is asynchronous - it completes in the background after
        the request. Installing a wheel library on a cluster is like running the pip
        command against the wheel file directly on driver and executors. All the
        dependencies specified in the library `setup.py` file are installed and this
        requires the library name to satisfy the wheel file name convention.
        The installation on the executors happens only when a new task is launched.
        With Databricks Runtime 7.1 and below, the installation order of libraries
        is nondeterministic. For wheel libraries in these versions, you can ensure a
        deterministic installation order by creating a zip file with suffix
        `.wheelhouse.zip` that includes all the wheel files.
        Check ["Install" libraries docs section](https://docs.databricks.com/dev-tools/api/latest/libraries.html#install).

        :param cluster_id: Unique identifier of the cluster whose status
            should be retrieved. This field is required.
        :type cluster_id: string
        :param libraries: An array of objects with the lib specs, according to the
           description in the [Library object docs](https://docs.databricks.com/dev-tools/api/latest/libraries.html#library).
        :type libraries: list
        :rtype: None
        """
        self.log.info(f"Installing libraries in cluster '{cluster_id}'...")
        self.libraries_client.install_libraries(
            cluster_id=cluster_id, libraries=libraries
        )

    def get_libraries_cluster_status(self, cluster_id):
        """
        Gets the status of libraries on a cluster. A status will be available for all
        libraries installed on the cluster via the API or the libraries UI as well as
        libraries set to be installed on all clusters via the libraries UI. If a library
        has been set to be installed on all clusters,`is_library_for_all_clusters`
        will be true, even if the library was also installed on the cluster.

        :param cluster_id: Unique identifier of the cluster whose status
            should be retrieved. This field is required.
        :type cluster_id: string
        :rtype: list[:class:LibraryStatus]
        """
        response = self.libraries_client.cluster_status(cluster_id=cluster_id)
        library_statuses = response.get("library_statuses", [])
        library_status_list = []
        for library_status in library_statuses:
            library_status_list.append(
                LibraryStatus(
                    library_status["library"],
                    library_status["status"],
                    library_status.get("is_library_for_all_clusters", False),
                    library_status.get("messages", []),
                )
            )

        return library_status_list

    def check_libraries_cluster_status(self, cluster_id, last_libs_status=None):
        """
        Checks if the libraries on a cluster are installed. When provided,
        may compare the retrieved libs status with the last libs status.

        :param cluster_id: Unique identifier of the cluster whose installation
            should be checked. This field is required.
        :type cluster_id: string
        :param last_libs_status: Dict with last libs status to be compared with
            the newly retrieved ones.
        :type last_libs_status: dict
        :rtype: dict{str: bool}
        """
        self.log.info(f"Checking libraries status for cluster '{cluster_id}'...")
        response = self.get_libraries_cluster_status(cluster_id)

        last_libs_status = last_libs_status or {}
        for lib_status in response:
            lib_status.raise_for_status()
            if lib_status.is_installed:
                if not last_libs_status.get(str(lib_status.library)):
                    self.log.info(
                        f"Library {lib_status.library} installed successfully "
                        f"in cluster '{cluster_id}'."
                    )
            else:
                self.log.info(
                    f"Library {lib_status.library} is yet to be installed, "
                    f"with installation status: {lib_status.status}"
                )
            last_libs_status.update({str(lib_status.library): lib_status.is_installed})
        return last_libs_status

    def grant_permissions(self, entity_type, entity_id, access_control_list):
        """
        Grants permissions for the provided entity to one or more users, groups, or
        service principals. This request only grants (adds) permissions. To revoke, use
        the replace all permissions operations. Check docs for info about entity types:
        - [clusters](https://docs.databricks.com/dev-tools/api/latest/permissions.html#operation/set-cluster-permissions)
        - [instance-pools](https://docs.databricks.com/dev-tools/api/latest/permissions.html#operation/set-instance-pool-permissions)
        - [jobs](https://docs.databricks.com/dev-tools/api/latest/permissions.html#operation/set-job-permissions)
        - [pipelines](https://docs.databricks.com/dev-tools/api/latest/permissions.html#operation/set-pipeline-permissions)
        - [notebooks](https://docs.databricks.com/dev-tools/api/latest/permissions.html#operation/set-notebook-permissions)
        - [directories](https://docs.databricks.com/dev-tools/api/latest/permissions.html#operation/get-directory-permissions)
        - [experiments](https://docs.databricks.com/dev-tools/api/latest/permissions.html#operation/set-experiment-permissions)
        - [registered-models](https://docs.databricks.com/dev-tools/api/latest/permissions.html#operation/set-registered-model-permissions)
        - [repos](https://docs.databricks.com/dev-tools/api/latest/permissions.html#operation/get-repo-permissions)

        :param entity_type: Databricks API entity type to determine which endpoint
            will be used. This field is required.
        :type entity_type: string
        :param entity_id: Unique identifier of the entity whose permissions
            will be granted. This field is required.
        :type entity_id: string
        :param access_control_list: Array of objects with user and permissions information.
        :type access_control_list: list
        """
        if entity_type not in API_ENTITY_TYPES:
            raise ValueError(
                "API entity type must be one of the "
                f"available API entities: {str(API_ENTITY_TYPES)}"
            )
        try:
            self.log.info(f"Granting permission to {entity_type} '{entity_id}'...")
            self.client.perform_query(
                "PATCH",
                path=f"/permissions/{entity_type}/{entity_id}",
                data={"access_control_list": access_control_list},
            )
            self.log.info(f"Permissions granted to {entity_type} '{entity_id}'.")
        # TO-DO: review permissions error handling, as we should assert that the proper permissions are provided
        except Exception as e:
            self.log.error(
                f"Error when granting permission to {entity_type} '{entity_id}'. "
                f"Exception={e}"
            )
