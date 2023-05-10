import os
from typing import Dict
from datetime import datetime
import json

import pendulum
from airflow.models import DAG
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from airflow.operators.dummy_operator import DummyOperator

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services import FileService
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum


class GsheetsDAGFactory:
    """
    Base class for building the Gsheets DAG flow, considering sheets by context.
    """

    LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
    ENV = os.environ.get("ENVIRONMENT")
    MAIN_START_DATE = datetime(2022, 2, 10, 0, 0, 0, tzinfo=LOCAL_TZ)

    gsheets_by_context_path = DAGPackagesPathService.get_dag_path(
        dag_name="gsheets_by_context"
    )
    GOOGLE_FILES_YAML_PATH = os.path.join(gsheets_by_context_path, "gsheets_files.yaml")
    GOOGLE_FILES = FileService.get_dict_from_yaml_file(GOOGLE_FILES_YAML_PATH)

    DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
        {
            "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
            "permission_level": ClusterPermissionEnum.MANAGE,
        }
    ]

    def __init__(self, source, source_with_context, task_pool):
        self.source, self.source_with_context, self.task_pool = (
            source,
            source_with_context,
            task_pool,
        )

        self.config_service = ConfigurationService(dag_name=source_with_context)

        artifacts_bucket = self.config_service.get_config("artifacts_bucket")
        databricks_bietlejuice_repo_path = self.config_service.get_config(
            "databricks_bietlejuice_repo_path"
        )

        (
            self.datalake_bucket,
            self.athena_query_results_bucket,
            self.doc_md_chart_url,
            self.spark_jobs_logs_path,
            self.default_libraries,
        ) = (
            self.config_service.get_config("datalake_bucket"),
            self.config_service.get_config("athena_query_results_bucket"),
            self.config_service.get_config("doc_md_chart_url"),
            self.config_service.get_config("spark_jobs_logs_path"),
            self.config_service.get_config("default_libraries"),
        )

        (
            self.raw_spark_job_path,
            self.base_spark_jobs_path,
            self.load_ids_to_be_ingested_info_spark_job,
        ) = (
            f"{databricks_bietlejuice_repo_path}/spark_jobs/{source_with_context}/load_{source_with_context}_into_datalake.py",
            f"{databricks_bietlejuice_repo_path}/spark_jobs/base/",
            f"{databricks_bietlejuice_repo_path}/spark_jobs/{source_with_context}/load_modified_gsheets_id.py",
        )

        # GSHEETS CONFIG
        self.custom_libraries = [
            {
                "whl": f"{artifacts_bucket}/gsheets-api-client-python/"
                f"quintoandar_gsheets_api_client-0.7.0-py2.py3-none-any.whl"
            },
            {"pypi": {"package": "google-auth==2.13.0"}},
            {"pypi": {"package": "google-api-python-client==2.55.0"}},
        ]

    def _get_cluster_description(self, cluster_name: str) -> Dict:
        """
        Obtains a dictionary with information about the cluster, using ConfigurationService.

        :param cluster_name: Name of the config file key with the cluster description.
        :type cluster_name: str
        :return: dict with the cluster description
        """
        return self.config_service.get_config(cluster_name)

    def __get_dag_doc_md(
        self, google_files, dag_context: str, dag_id: str, dag_doc_details: Dict
    ) -> str:
        """
        Format the Markdown document for the specified context.
        @param google_files: the dict_items with the general information of the
        context sheets.
        @param dag_context: a str with the name of the context/DAG.
        @param dag_id: a str with the id of the context/DAG.
        @param dag_doc_details: a dictionary with documentary details about the DAG.
        @return: string.
        """

        trigger_interval = (
            dag_doc_details.get("trigger_interval") if dag_doc_details else None
        )
        additional_information = (
            dag_doc_details.get("additional_information") if dag_doc_details else None
        )

        doc_md = BaseDAG.get_dag_doc(self.source_with_context)

        raw_tables = list(map(self.__get_table_name, google_files))
        clean_tables = list(
            map(
                lambda google_file: self.__get_table_name(google_file, layer="clean"),
                google_files,
            )
        )
        return doc_md.format(
            dag_context=dag_context.upper().replace("_", " "),
            raw_tables="".join(raw_tables),
            clean_tables="".join(clean_tables),
            chart_url=self.doc_md_chart_url,
            dag_id=dag_id,
            trigger_interval=trigger_interval if trigger_interval else "daily",
            additional_information=(
                f"\n\n### Additional Information\n\n{additional_information}"
                if additional_information
                else ""
            ),
        )

    @staticmethod
    def __filtering_gsheets_from_context(google_file, dag_context: str) -> Dict:
        """
        This method filters and returns the sheets added for the specified context.
        @param google_file: a dict_items with the general information of the sheets.
        @param dag_context: a str with the name of the context/DAG that should be
        considered in the filter.
        @return: dict_items
        """
        sheet_details = list(google_file)[1]
        if sheet_details["sheet_context"] == dag_context:
            return google_file

    @staticmethod
    def __get_table_name(google_file, layer="raw") -> str:
        """
        Get the raw/clean table name from the specified gsheets file.
        @param google_file: a dict_items with the general information of the sheets.
        @param layer: raw/clean. Defines the layer from which you want to get
        the name of the table.
        @return: string
        """
        if layer == "raw":
            table_name = google_file[0]
        else:
            table_name = google_file[1]["clean_table_name"]

        return f"    - `{table_name}` \n"

    @staticmethod
    def __create_raw_tasks(
        google_files,
        source,
        task_pool,
        raw_spark_job_path,
        task_group,
        dag_context,
        execution_date,
    ):
        """
        This method creates the raw task for each worksheet associated with the DAG
        context.
        @param google_files: the dict_items with the general information of the
        context sheets.
        @param source: a str with source name.
        @param task_pool: a str with airflow's pool name
        @param raw_spark_job_path: full filepath for the extraction spark job.
        @param task_group: BaseTaskGroup.
        @return: dict
        """
        raw_task_groups = {}

        for table_name, sheet_details in google_files:
            sheet_details["raw_table_name"] = table_name

            raw_task_group = task_group.build_raw_task_group_for_single_table(
                source=source,
                table_name=table_name,
                target_database_base_name=source,
                extraction_spark_job_file=raw_spark_job_path,
                raw_spark_job_extra_args=[
                    source,
                    table_name,
                    json.dumps(sheet_details),
                ],
                pool=task_pool,
                tree_path=f"{dag_context}/",
            )
            raw_task_groups[sheet_details["clean_table_name"]] = raw_task_group

        return raw_task_groups

    @staticmethod
    def __create_done_tasks(google_files):
        """
        This method creates the done task for each worksheet associated with the DAG
        context.
        @param google_files: the dict_items with the general information of the
        context sheets.
        @return: dict
        """
        done_task_groups = {}

        for table_name, sheet_details in google_files:
            clean_table_name = sheet_details["clean_table_name"]
            task_id = f"done-clean-{clean_table_name}".replace("_", "-")

            done_task_group = [
                DummyOperator(task_id=task_id, trigger_rule="one_success")
            ]
            done_task_groups[
                clean_table_name
            ] = DatalakeTaskGroup.format_tasks_boundaries(
                done_task_group, done_task_group
            )

        return done_task_groups

    def __create_load_ingestion_ids_info_task(self, task_pool, dag_context, dag):
        return QuintoAndarDatabricksSubmitRunOperator(
            task_id="ingested-gsheets-id-info",
            dag=dag,
            pool=task_pool,
            json={
                "spark_python_task": {
                    "python_file": self.load_ids_to_be_ingested_info_spark_job,
                    "parameters": [self.ENV, self.datalake_bucket, dag_context],
                }
            },
            do_output_xcom_push=True,
        )

    def build_dag(
        self, dag_context, dag_details, execution_date, user_defined_macros=None
    ):
        """
        This method builds a DAG from the given context and details.
        @param dag_context: str. DAG name.
        @param dag_details: json. Details about the DAG.
        @param execution_date: str. DAG execution date.
        @param user_defined_macros: dict. DAG macros to be defined.
        """

        dag_name = f"{self.source}.{dag_context}"
        dag_id = f"bietlejuice.{dag_name}"

        main_schedule_interval = dag_details.get("main_schedule_interval")

        cluster_description = self._get_cluster_description(
            dag_details.get("cluster_name", "databricks_10_4_min_general_cluster")
        )

        google_files_context = list(
            filter(
                lambda google_file: self.__filtering_gsheets_from_context(
                    google_file, dag_context
                ),
                self.GOOGLE_FILES.items(),
            )
        )

        dag = DAG(
            dag_id=dag_id,
            default_args={
                "owner": dag_details["dag_owner"],
                "wait_for_downstream": False,
                "depends_on_past": False,
            },
            start_date=self.MAIN_START_DATE,
            schedule_interval=main_schedule_interval,
            doc_md=self.__get_dag_doc_md(
                google_files_context, dag_context, dag_id, dag_details.get("dag_doc")
            ),
            user_defined_macros=user_defined_macros,
        )

        create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
            dag=dag,
            task_id="create-cluster",
            cluster_configuration=cluster_description,
            libraries=self.default_libraries + self.custom_libraries,
            access_control_list=self.DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST,
        )

        task_group = DatalakeTaskGroup(
            dag=dag,
            env=self.ENV,
            datalake_bucket=self.datalake_bucket,
            relative_query_path=self.source_with_context,
            spark_jobs_path=self.base_spark_jobs_path,
            athena_query_result_location=self.athena_query_results_bucket,
        )

        load_ids_to_be_ingested_task_group = self.__create_load_ingestion_ids_info_task(
            task_pool=self.task_pool, dag_context=dag_context, dag=dag
        )

        raw_task_groups = self.__create_raw_tasks(
            google_files_context,
            self.source,
            self.task_pool,
            self.raw_spark_job_path,
            task_group,
            dag_context,
            execution_date,
        )

        task_group.relative_query_path = self.source_with_context

        clean_task_groups = task_group.build_task_group_from_sql_files(
            layer=LayerEnum.CLEAN,
            source_database_base_name=self.source,
            target_database_base_name=self.source,
            tree_path=f"{dag_context}/",
        )

        done_task_groups = self.__create_done_tasks(google_files_context)

        terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
            dag=dag, task_id="terminate-cluster"
        )

        return (
            dag,
            create_cluster_task,
            load_ids_to_be_ingested_task_group,
            raw_task_groups,
            clean_task_groups,
            done_task_groups,
            terminate_cluster_task,
        )
