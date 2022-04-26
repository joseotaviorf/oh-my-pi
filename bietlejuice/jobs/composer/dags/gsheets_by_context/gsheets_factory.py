import os
from datetime import datetime
import json

import pendulum
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG
from bietlejuice.jobs.composer.base.pipeline.layer_enum import LayerEnum
from bietlejuice.jobs.composer.dags.base.datalake_task_group import DatalakeTaskGroup
from bietlejuice.jobs.composer.services import FileService
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)


class GsheetsDAGFactory:
    """
    Base class for building the Gsheets DAG flow, considering sheets by context.
    """

    LOCAL_TZ = pendulum.timezone("America/Sao_Paulo")
    ENV = os.environ.get("ENVIRONMENT")
    MAIN_START_DATE = datetime(2022, 2, 10, 0, 0, 0, tzinfo=LOCAL_TZ)

    CLUSTER_DESCRIPTION = Variable.get(
        "databricks_9_1_min_general_cluster", deserialize_json=True
    )

    GOOGLE_FILES_YAML_PATH = os.path.join(
        os.path.dirname(os.path.realpath(__file__)), "gsheets_files.yaml"
    )
    GOOGLE_FILES = FileService.get_dict_from_yaml_file(GOOGLE_FILES_YAML_PATH)

    def __init__(self, source, source_with_context, task_pool):
        self.source, self.source_with_context, self.task_pool = (
            source,
            source_with_context,
            task_pool,
        )

        config_service = ConfigurationService(
            dag_name=source_with_context, env=self.ENV
        )

        artifacts_s3_bucket = config_service.get_config("artifacts_bucket")
        databricks_bietlejuice_repo_path = config_service.get_config(
            "databricks_bietlejuice_repo_path"
        )

        (
            self.datalake_bucket,
            self.athena_query_results_bucket,
            self.doc_md_chart_url,
            self.spark_jobs_logs_path,
        ) = (
            config_service.get_config("datalake_bucket"),
            config_service.get_config("athena_query_results_bucket"),
            config_service.get_config("doc_md_chart_url"),
            config_service.get_config("spark_jobs_logs_path"),
        )

        self.raw_spark_job_path, self.base_spark_jobs_path = (
            f"{databricks_bietlejuice_repo_path}/spark_jobs/{source_with_context}/load_{source_with_context}_into_datalake.py",
            f"{databricks_bietlejuice_repo_path}/spark_jobs/base/",
        )

        # GSHEETS CONFIG
        self.custom_libraries = [
            {
                "whl": f"{artifacts_s3_bucket}/gsheets-api-client-python/"
                f"quintoandar_gsheets_api_client-0.2.1-py2.py3-none-any.whl"
            }
        ]

    @staticmethod
    def __filtering_gsheets_from_context(google_file, dag_context):
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
    def __create_raw_tasks(
        google_files,
        source,
        task_pool,
        raw_spark_job_path,
        create_cluster_task,
        task_group,
    ):
        """
        This method creates the raw task for each worksheet associated with the DAG
        context.
        @param google_files: the dict_items with the general information of the
        context sheets.
        @param source: a str with source name.
        @param task_pool: a str with airflow's pool name
        @param raw_spark_job_path: full filepath for the extraction spark job.
        @param create_cluster_task: QuintoAndarDatabricksCreateClusterOperator.
        @param task_group: BaseTaskGroup.
        @return: dict
        """
        raw_task_groups = {}

        for table_name, sheet_details in google_files:

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
            )
            raw_task_groups[sheet_details["clean_table_name"]] = raw_task_group

            create_cluster_task >> DatalakeTaskGroup.first_tasks(raw_task_group)

        return raw_task_groups, create_cluster_task

    def build_dag(self, dag_context, dag_details):
        """
        This method builds a DAG from the given context and details.
        @param dag_context: str. DAG name.
        @param dag_details: json. Details about the DAG.
        """

        dag_name = f"{self.source}.{dag_context}"
        dag_id = f"bietlejuice.{dag_name}"

        main_schedule_interval = dag_details.get("main_schedule_interval")

        self.CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"][
            "destination"
        ] = f"{self.spark_jobs_logs_path}{dag_id}"

        dag = DAG(
            dag_id=dag_id,
            default_args={
                "owner": dag_details["dag_owner"],
                "wait_for_downstream": False,
                "depends_on_past": False,
            },
            start_date=self.MAIN_START_DATE,
            schedule_interval=main_schedule_interval,
            doc_md=BaseDAG.get_dag_doc(f"gsheets_by_context/{dag_context}").format(
                chart_url=self.doc_md_chart_url, dag_id=dag_id
            ),
        )

        create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
            dag=dag,
            task_id="create-cluster",
            cluster_configuration=self.CLUSTER_DESCRIPTION,
            libraries=self.custom_libraries,
        )

        task_group = DatalakeTaskGroup(
            dag=dag,
            env=self.ENV,
            datalake_bucket=self.datalake_bucket,
            relative_query_path=self.source,
            spark_jobs_path=self.base_spark_jobs_path,
            athena_query_result_location=self.athena_query_results_bucket,
        )

        google_files_context = list(
            filter(
                lambda google_file: self.__filtering_gsheets_from_context(
                    google_file, dag_context
                ),
                self.GOOGLE_FILES.items(),
            )
        )

        raw_task_groups, create_cluster_task = self.__create_raw_tasks(
            google_files_context,
            self.source,
            self.task_pool,
            self.raw_spark_job_path,
            create_cluster_task,
            task_group,
        )

        clean_task_groups = task_group.build_task_group_from_sql_files(
            layer=LayerEnum.CLEAN,
            source_database_base_name=self.source,
            target_database_base_name=self.source,
            tree_path=f"{dag_context}/",
        )

        return dag, raw_task_groups, clean_task_groups
