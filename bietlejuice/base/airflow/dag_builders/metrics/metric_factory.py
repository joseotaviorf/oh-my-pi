import os
from datetime import datetime
import yaml

import pendulum
from airflow.models import DAG
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)
from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.services import ConfigurationService


from bietlejuice.dags.base.datalake_task_group import DatalakeTaskGroup


class MetricsDagFactory:
    """
    Base class for building the Metric Layer Dags. It
    will created one different Dag per domain using
    a config file define by line.
    """

    BUSINESS_DOMAIN_DELIMITER = "__"

    LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
    MAIN_START_DATE = datetime(2020, 7, 1, 0, 0, 0, tzinfo=LOCAL_TZ)
    ENV = os.environ.get("ENVIRONMENT")

    DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
        {
            "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
            "permission_level": ClusterPermissionEnum.MANAGE,
        }
    ]

    METRIC_ROOT = os.path.dirname(__file__)

    def __init__(self, dag_name):
        """
        :param dag_name: dag_name is composed by {business_unit}__{domain}.
            For metrics with alpha maturity it will be alpha__{domain}.
        :type dag_name: str
        """
        self.dag_name = dag_name
        self.business_unit, self.domain = self.dag_name.split(
            self.BUSINESS_DOMAIN_DELIMITER
        )
        self.business_unit = self.business_unit.replace("metric_", "")
        self.dag_id = f"bietlejuice.{self.dag_name}"
        self.config_service = ConfigurationService(dag_name=self.dag_name)
        self.dag_configuration = self.get_dag_configuration()
        self.cluster_description = self.config_service.get_config("custom_cluster")
        self.domain_details = self.dag_configuration["domain_details"]
        self.set_general_configs()
        self.table_names = self.list_domain_tables()
        self.owner = self.dag_configuration["owner"]
        self._dag_end_date = None

    @property
    def dag_end_date(self):
        return self._dag_end_date

    @dag_end_date.setter
    def dag_end_date(self, value):
        if self.business_unit == "alpha":
            try:
                end_date = datetime.strptime(
                    self.dag_configuration["dag_end_date"], "%Y-%m-%d"
                )
                value = end_date.replace(tzinfo=self.LOCAL_TZ)
            except IndexError:
                raise KeyError(
                    """You are trying to create a alpha Dag without a defined end_date."
                    Set dag_end_date in your config file to limit the time of your tests."
                    dag_end_date has the format yyyy-mm-dd."""
                )

        self._dag_end_date = value

    def get_dag_configuration(self):
        dag_path = DAGPackagesPathService.get_dag_path(self.dag_name)
        dag_config_path = f"{dag_path}/{self.dag_name}.yml"
        with open(dag_config_path) as conf_file:
            dag_configuration = yaml.safe_load(conf_file)

        return dag_configuration

    def set_general_configs(self):
        self.athena_query_results_bucket = self.config_service.get_config(
            "athena_query_results_bucket"
        )
        databricks_bietlejuice_repo_path = self.config_service.get_config(
            "databricks_bietlejuice_repo_path"
        )
        self.base_spark_job_path = (
            f"{databricks_bietlejuice_repo_path}/spark_jobs/base/"
        )
        self.metrics_bucket = self.config_service.get_config("metrics_bucket")

    def list_domain_tables(self):
        """ Get tables from sqls.
        """
        table_names = DAGPackagesPathService.list_queries_files_in_composer(
            dag_name=self.dag_name, layer=LayerEnum.METRIC.value
        )
        table_names = sorted(table_names)
        return table_names

    def build_doc_md(self):
        """ Fill doc with customized information
        """
        doc_md = BaseDAG.get_dag_doc("metric", template_path=self.METRIC_ROOT)
        tables = "\n - ".join([f"`{table}`" for table in self.table_names])

        return doc_md.format(
            business_unit=self.business_unit,
            domain=self.domain,
            brief_context=self.domain_details["brief_description"],
            tables=tables,
            chart_url=self.config_service.get_config("doc_md_chart_url"),
            dag_id=self.dag_id,
        )

    def build_dag(self):
        """ Create a dag and its tasks.
        """
        self.dag_end_date = None
        dag = DAG(
            dag_id=self.dag_id,
            default_args={
                "owner": getattr(DAGOwnerEnum, self.owner),
                "wait_for_downstream": False,
                "depends_on_past": False,
            },
            start_date=self.MAIN_START_DATE,
            end_date=self.dag_end_date,
            schedule_interval=None,
            doc_md=self.build_doc_md(),
        )

        tasks = self.build_tasks(dag)
        self.set_cluster_borders(dag, tasks)

        return dag

    def set_cluster_borders(self, dag, tasks):
        """
        Method to create and terminate cluster.
        """
        create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
            dag=dag,
            task_id="create-cluster",
            cluster_configuration=self.cluster_description,
            access_control_list=self.DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
        )

        terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
            dag=dag, task_id="terminate-cluster"
        )

        create_cluster_task.set_downstream(DatalakeTaskGroup.all_first_tasks(tasks))
        terminate_cluster_task.set_upstream(DatalakeTaskGroup.all_last_tasks(tasks))

        # Set data quality tasks. Here it must exist
        independent_tasks = DatalakeTaskGroup.all_independent_tasks(tasks)
        if independent_tasks:
            terminate_cluster_task.set_upstream(independent_tasks)

    def build_tasks(self, dag):
        """
        This method will split tables between
        standard and custom. Standards will
        be tables with full load and without
        any special parameter.
        """

        datalake_task_group = DatalakeTaskGroup(
            dag=dag,
            env=self.ENV,
            datalake_bucket=self.metrics_bucket,
            relative_query_path=self.dag_name,
            spark_jobs_path=self.base_spark_job_path,
            athena_query_result_location=self.athena_query_results_bucket,
        )

        custom_tables_configs = self.dag_configuration.get("custom_tables_configs", {})
        custom_tables = custom_tables_configs.keys()
        standard_tables = set(self.table_names) - set(custom_tables)

        custom_tables
        task_groups = {}

        common_params = {
            "layer": LayerEnum.METRIC,
            "source_database_base_name": self.business_unit,
            "target_database_base_name": self.business_unit,
            "has_create_external_table_task": False,
        }

        for table in custom_tables:
            custom_table_config = custom_tables_configs[table]
            task_group_params = {
                **common_params,
                **custom_table_config,
                "table_name": table,
            }

            task_groups[table] = datalake_task_group._build_task_group(
                **task_group_params
            )

        for table in standard_tables:
            task_group_params = {**common_params, "table_name": table}
            task_groups[table] = datalake_task_group._build_task_group(
                **task_group_params
            )

        return task_groups
