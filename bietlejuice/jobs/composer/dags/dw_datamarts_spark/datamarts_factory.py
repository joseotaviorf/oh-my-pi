import os
from datetime import datetime

import pendulum
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from airflow.utils.helpers import chain

from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.base.airflow.helpers import TaskFlowHelper
from bietlejuice.jobs.composer.dags.base.dw_task_group import DWTaskGroup
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)


class DatamartsDAGFactory:
    """
    Base class for building the Datamarts DAG flow.
    """

    LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
    MAIN_START_DATE = datetime(2020, 8, 29, 0, 0, 0, tzinfo=LOCAL_TZ)
    DW_SCHEMA = "datamarts"

    def __init__(self, source):
        self.source = source
        self.env = os.environ.get("ENVIRONMENT")

        config_service = ConfigurationService(dag_name=source, env=self.env)

        self.doc_md_chart_url = config_service.get_config("doc_md_chart_url")
        self.spark_jobs_logs_path = config_service.get_config("spark_jobs_logs_path")
        self.dw_bucket = config_service.get_config("dw_bucket")
        self.databricks_bietlejuice_repo_path = config_service.get_config(
            "databricks_bietlejuice_repo_path"
        )
        self.spectrum_iam_role = config_service.get_config("spectrum_iam_role")

        self.spark_jobs_path = (
            f"{self.databricks_bietlejuice_repo_path}/spark_jobs/base/"
        )

    def _get_cluster_description(self, dag_id, cluster_name):
        """
        Obtains a dictionary with information about the cluster, using an Airflow variable.

        :param dag_id: Full name of the DAG.
        :type dag_id: str
        :param cluster_name: Name of the Airflow variable with the cluster description.
        :type cluster_name: str
        :return: dict with the cluster description
        """

        cluster_description = Variable.get(cluster_name, deserialize_json=True)
        cluster_description["spark_env_vars"]["ENVIRONMENT"] = self.env
        cluster_description["cluster_log_conf"]["s3"][
            "destination"
        ] = f"{self.spark_jobs_logs_path}{dag_id}"

        return cluster_description

    @staticmethod
    def _create_inner_dependencies_dictionary(context_datamarts):
        inner_dependencies = {}

        for datamart_configs in context_datamarts.values():
            for table_name, table_content in datamart_configs.items():
                if "depends_on" in table_content:
                    inner_dependencies[table_name] = table_content["depends_on"]

        return inner_dependencies

    def _build_datamart_tasks(self, task_group, context_datamarts):
        """
        With the task group, context and datamart configs, creates the staging and DW tasks for the datamarts.

        :param task_group: DW Task Group object
        :type task_group: DWTaskGroup
        :param dag_context: Context of the datamart
        :type dag_context: str
        :param context_datamarts: Configs for the datamarts in that context
        :type context_datamarts: dict
        :return: dicts datamart_task_groups and dw_task_group_boundaries
        """

        datamart_task_groups = {"staging": {}, "dw": {}}
        dw_task_group_boundaries = {}

        for tree_path, tree_path_configs in context_datamarts.items():
            for table_name in tree_path_configs:
                datamart_task_groups["staging"][
                    table_name
                ] = task_group.build_dw_staging_task_group(
                    table_name=table_name, tree_path=tree_path
                )
                datamart_task_groups["dw"][table_name] = task_group.build_dw_task_group(
                    table_name=table_name,
                    spectrum_iam_role=self.spectrum_iam_role,
                    has_load_to_redshift_task=False,
                )
                dw_task_group_boundaries[
                    table_name
                ] = DWTaskGroup.format_tasks_boundaries(
                    initial_tasks=DWTaskGroup.first_tasks(
                        datamart_task_groups["staging"][table_name]
                    ),
                    final_tasks=DWTaskGroup.last_tasks(
                        datamart_task_groups["dw"][table_name]
                    ),
                )

        return datamart_task_groups, dw_task_group_boundaries

    def build_dag(self, dag_context, dag_details, context_datamarts):
        """
        This method builds a Datamart DAG from the given context and details.
        :param dag_context: Name of the context being built.
        :type dag_context: str
        :param dag_details: Contains information about DAG owner and (optional) cluster name.
        :type dag_details: dict
        :param context_datamarts: Contains the datamart names and their configs, such as query path and inner dependencies
        :type context_datamarts: dict
        :return: DAG
        """

        dag_name = f"{self.source}.{dag_context}"
        dag_id = f"bietlejuice.{dag_name}"

        cluster_description = self._get_cluster_description(
            dag_id, dag_details.get("cluster_name", "databricks_default_cluster")
        )

        dag = DAG(
            dag_id=dag_id,
            default_args={
                "owner": dag_details["owner"],
                "wait_for_downstream": False,
                "depends_on_past": False,
            },
            start_date=self.MAIN_START_DATE,
            schedule_interval=None,
            doc_md=BaseDAG.get_dag_doc(
                f"dw_datamarts_spark/{dag_context}/{dag_context}"
            ).format(chart_url=self.doc_md_chart_url, dag_id=dag_id),
        )

        create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
            dag=dag, task_id="create-cluster", cluster_configuration=cluster_description
        )

        terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
            dag=dag, task_id="terminate-cluster"
        )

        task_group = DWTaskGroup(
            dag=dag,
            env=self.env,
            dw_bucket=self.dw_bucket,
            dw_schema=self.DW_SCHEMA,
            relative_query_path=self.source,
            spark_jobs_path=self.spark_jobs_path,
        )

        datamart_task_groups, dw_task_group_boundaries = self._build_datamart_tasks(
            task_group=task_group, context_datamarts=context_datamarts
        )

        (
            task_groups_boundaries_without_inner_dependencies,
            inner_dependencies_task_groups_boundaries,
        ) = task_group.set_inner_dag_dependencies(
            task_flow_helper=TaskFlowHelper(),
            task_groups_boundaries=dw_task_group_boundaries,
            dag_inner_dependencies=DatamartsDAGFactory._create_inner_dependencies_dictionary(
                context_datamarts
            ),
        )

        chain(
            create_cluster_task,
            DWTaskGroup.all_first_tasks(
                task_groups_boundaries_without_inner_dependencies
            )
            + DWTaskGroup.first_tasks(inner_dependencies_task_groups_boundaries),
        )

        TaskFlowHelper.chain_task_groups_via_common_table(
            datamart_task_groups["staging"], datamart_task_groups["dw"]
        )

        chain(
            DWTaskGroup.all_last_tasks(datamart_task_groups["dw"]),
            terminate_cluster_task,
        )

        return dag
