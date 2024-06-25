import os
import json
from typing import Dict, AnyStr

from databricks_plugin import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from airflow.operators.dummy_operator import DummyOperator
from airflow.operators.python_operator import BranchPythonOperator
from airflow.utils.helpers import chain

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow import (
    BaseWorkflow,
)
from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.formatters import StringFormatter
from bietlejuice.base.api import APIEnum


def get_run_param(dag_run, param_name):
    return dag_run.conf.get(param_name) if dag_run.conf else []


class RawGsheetsWorkflow(BaseWorkflow):
    """
    Inherits the dag build base to define the flow that creates tasks from sql files.
    :param dag_args: A dictionary containing the definition of the dag with parameters received from each dag yaml file.
    :param workflow_args: A dictionary containing arguments that will be used to decide which tasks to define in the dag.
    :param cluster_args: A dictionary containing arguments that will be used for the cluster definition that the dag processes will make.
    """

    DEFAULT_DAG_DOCUMENTATION = {
        "dag_purpose": "This DAG extracts data from Google Sheets files for {dag_context} Context.",
        "additional_information": """### How to force run a gsheet

    If you need to bypass the check for updated on a specific sheet, pass the following JSON to the DAG Config arguments, but change the example table names for the clean table name of your sheet:

    ```
    {{\"bypass_update_check_list\":[\"events_aud\",\"ciq_table\"]}}
    ```""",
    }
    DUMMY_TASK_PREFIX = "dummy"
    DONE_TASK_PREFIX = "done-clean"
    IDS_TO_BE_INGESTED_TASK_ID = "ingested-gsheets-id-info"

    def __init__(self, dag_args, workflow_args, cluster_args):
        super().__init__(dag_args, workflow_args, cluster_args)
        self.dag_args["documentation"] = self.DEFAULT_DAG_DOCUMENTATION
        self.dag_args["documentation"]["dag_purpose"] = self.DEFAULT_DAG_DOCUMENTATION[
            "dag_purpose"
        ].format(dag_context=self.dag_name.replace("gsheets_", ""))
        self.env = os.environ.get("ENVIRONMENT")
        bucket_config = workflow_args.get("bucket_config_name", "datalake_bucket")
        self.datalake_bucket = self.config_service.get_config(bucket_config)
        self.task_pool = "gsheets_pool"
        self.databricks_bietlejuice_repo_path = self.config_service.get_config(
            "databricks_bietlejuice_repo_path"
        )
        self.base_spark_jobs_path = (
            f"{self.databricks_bietlejuice_repo_path}/spark_jobs/base/"
        )
        self.has_hive_sync = workflow_args.get("has_hive_sync", True)

        CREDENTIALS_SCOPE = {
            "quintoandar": APIEnum.GSHEETS_CREDENTIALS,
            "people": APIEnum.GSHEETS_CREDENTIALS_PEOPLE,
        }
        self.credentials_scope = workflow_args.get("credentials_scope", "quintoandar")
        self.credentials_key = CREDENTIALS_SCOPE[self.credentials_scope]
        self.dag = self.dag_instance()

    def build_dag(self):
        schema = self.workflow_args.get("custom_schema", "gsheets")
        tables_customization = list(
            self.config_service.get_config("sheets_info").items()
        )

        cluster_params = self.get_cluster_params()

        self.dag.user_defined_macros = {"get_run_param": get_run_param}
        self.dag.doc_md = self._get_dag_documentation()

        create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
            dag=self.dag,
            task_id="create-cluster",
            cluster_configuration=cluster_params["cluster_config"],
            libraries=cluster_params["libraries"],
            access_control_list=cluster_params["access_control_list"],
        )

        task_group = DatalakeTaskGroup(
            dag=self.dag,
            env=self.env,
            datalake_bucket=self.datalake_bucket,
            relative_query_path=self.dag_name,
            spark_jobs_path=self.base_spark_jobs_path,
        )

        load_ids_to_be_ingested_task_group = self._set_load_ingestion_ids_info_task(
            task_pool=self.task_pool, dag_name=self.dag_name, dag=self.dag
        )

        raw_task_groups = self._set_raw_tasks(
            tables_customization,
            self.dag_name,
            schema,
            self.task_pool,
            f"{self.base_spark_jobs_path}load_gsheets_into_datalake.py",
            task_group,
        )

        dummy_tasks = self._set_dummy_tasks(raw_task_groups=raw_task_groups)
        branch_tasks = self._set_check_task(
            raw_task_groups=raw_task_groups, dummy_tasks=dummy_tasks
        )

        clean_task_groups = task_group.build_task_group_from_sql_files(
            layer=LayerEnum.CLEAN,
            source_database_base_name=schema,
            target_database_base_name=schema,
            has_hive_sync=self.has_hive_sync,
        )

        done_tasks = self._set_done_tasks(tables_customization)

        terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
            dag=self.dag, task_id="terminate-cluster", trigger_rule="all_done"
        )

        self.set_dependencies(
            create_cluster_task=create_cluster_task,
            load_ids_to_be_ingested_task_group=load_ids_to_be_ingested_task_group,
            branch_tasks=branch_tasks,
            dummy_tasks=dummy_tasks,
            raw_task_groups=raw_task_groups,
            clean_task_groups=clean_task_groups,
            done_task_groups=done_tasks,
            terminate_cluster_task=terminate_cluster_task,
        )

        return self.dag

    def _set_dummy_tasks(self, raw_task_groups) -> Dict:
        """
        This dummy task has the function similar to the bypass task on the sync task groups. It was necessary
        to add a task between the check and done tasks for the branch operator to work.
        @param raw_task_groups: A dict containing the raw tasks for each gsheet.
        @return:
        """
        dummy_tasks = {
            gsheet_name: DummyOperator(
                task_id=StringFormatter.slugify(
                    f"{self.DUMMY_TASK_PREFIX}-{gsheet_name}"
                )
            )
            for gsheet_name in raw_task_groups
        }

        return dummy_tasks

    def _set_check_task(self, raw_task_groups: Dict, dummy_tasks: Dict) -> Dict:
        """
        Create the task that will decide which branch the DAG will follow using the
        BranchOperator.
        @param raw_task_groups: Dict containing the raw tasks for each gsheet.
        @return: dict for each gsheet containing a BranchPythonOperator.
        """
        branch_tasks = {
            gsheet: BranchPythonOperator(
                task_id=StringFormatter.slugify(f"check-{gsheet}-should-run"),
                python_callable=self.decide_branch,
                retries=3,
                op_kwargs={
                    "table_name": gsheet,
                    "gsheet_raw_task_group": raw_task_groups[gsheet],
                    "dummy_task": dummy_tasks[gsheet],
                    "bypass_update_check_list": "{{ get_run_param(dag_run, 'bypass_update_check_list') }}",
                },
                provide_context=True,
            )
            for gsheet in raw_task_groups
        }
        return branch_tasks

    def set_dependencies(
        self,
        create_cluster_task,
        load_ids_to_be_ingested_task_group,
        branch_tasks,
        dummy_tasks,
        raw_task_groups,
        clean_task_groups,
        done_task_groups,
        terminate_cluster_task,
    ) -> None:
        for gsheet in raw_task_groups:
            dummy_task = dummy_tasks[gsheet]
            branch_task = branch_tasks[gsheet]
            chain(
                create_cluster_task,
                load_ids_to_be_ingested_task_group,
                branch_task,
                DatalakeTaskGroup.first_tasks(raw_task_groups[gsheet]),
            )

            chain(branch_task, dummy_task)
            chain(dummy_task, DatalakeTaskGroup.first_tasks(done_task_groups[gsheet]))

        TaskFlowHelper.chain_task_groups_via_common_table(
            raw_task_groups, clean_task_groups
        )
        TaskFlowHelper.chain_task_groups_via_common_table(
            clean_task_groups, done_task_groups
        )

        terminate_cluster_task.set_upstream(
            DatalakeTaskGroup.all_last_tasks(done_task_groups)
        )

        # Set data quality tasks if exists
        independent_tasks = DatalakeTaskGroup.all_independent_tasks(
            raw_task_groups
        ) + DatalakeTaskGroup.all_independent_tasks(clean_task_groups)

        if independent_tasks:
            terminate_cluster_task.set_upstream(independent_tasks)

    def get_cluster_params(self):
        cluster_configuration = self.config_service.get_config(
            self.cluster_args["type"]
        )
        default_libraries = self.config_service.get_config("default_libraries")
        custom_libraries = [
            {
                lib_type: lib_name.format(
                    artifacts_bucket=self.config_service.get_config("artifacts_bucket")
                )
            }
            if isinstance(lib_name, str)
            else {lib_type: lib_name}
            for custom_libraries in self.cluster_args["custom_libraries"]
            for lib_type, lib_name in custom_libraries.items()
        ]

        access_control_list_from_yml = self.cluster_args["access_control_list"]
        databricks_access_control_list = [
            {
                "group_name": access_control_list_from_yml["group_name"],
                "permission_level": access_control_list_from_yml["permission_level"],
            }
        ]
        return {
            "cluster_config": cluster_configuration,
            "libraries": default_libraries + custom_libraries,
            "access_control_list": databricks_access_control_list,
        }

    def decide_branch(
        self,
        table_name: str,
        gsheet_raw_task_group: QuintoAndarDatabricksSubmitRunOperator,
        dummy_task: DummyOperator,
        bypass_update_check_list=[],
        **kwargs,
    ) -> AnyStr:
        """
        Function passed to the BranchOperator that will evaluate which path the DAG should
        follow:
         1 - Load the new data
         2 - Skip the ingestion
        It will decide be pulling the gsheets IDs from XCom and comparing if the current gsheet
        name is on the list.
        @param table_name: Gsheets clean table name.
        @param gsheet_raw_task_group: Gsheet raw task.
        @param dummy_task: Gsheet dummy task.
        @param bypass_update_check_list: Bypass list to indicate that this gsheet should run. Force run.
        @param kwargs: Task kwargs according to BranchOperator docs.
        @return: Next task name from the branch that will run.
        """
        to_ingest_output_json = kwargs["ti"].xcom_pull(
            task_ids=self.IDS_TO_BE_INGESTED_TASK_ID, key="output"
        )

        to_ingest_output = json.loads(to_ingest_output_json)
        if (
            not to_ingest_output["success_run"]
            or table_name in to_ingest_output["sheets_to_be_ingested"]
            or table_name in bypass_update_check_list
        ):
            return DatalakeTaskGroup.first_tasks(gsheet_raw_task_group)[0].task_id
        else:
            return dummy_task.task_id

    def _set_load_ingestion_ids_info_task(
        self, task_pool: str, dag_name: str, dag
    ) -> QuintoAndarDatabricksSubmitRunOperator:
        """
        This task is the first to run and will define which gsheet should run on this DAG Run.
        It will search for the gsheets with modification on the last 24h and the ones that uses
        the IMPORTRANGE function.
        @param task_pool: Task pool name.
        @param dag_name: DAG name that will be passed as param to the spark job.
        @param dag: DAG instance.
        @return: QuintoAndarDatabricksSubmitRunOperator
        """
        return QuintoAndarDatabricksSubmitRunOperator(
            task_id=self.IDS_TO_BE_INGESTED_TASK_ID,
            dag=dag,
            pool=task_pool,
            json={
                "spark_python_task": {
                    "python_file": f"{self.base_spark_jobs_path}load_modified_gsheets_id.py",
                    "parameters": [
                        self.env,
                        self.datalake_bucket,
                        dag_name,
                        self.credentials_key,
                        self.credentials_scope,
                    ],
                }
            },
            do_output_xcom_push=True,
        )

    def _set_raw_tasks(
        self,
        google_files: dict,
        dag_name: str,
        schema: str,
        task_pool: str,
        raw_spark_job_path: str,
        task_group: DatalakeTaskGroup,
    ) -> Dict:
        """
        This method creates the raw task for each worksheet associated with the DAG
        context.
        @param google_files: the dict_items with the general information of the
        context sheets.
        @param dag_name: a str with DAG name.
        @param schema: a str with schema name.
        @param task_pool: a str with airflow's pool name
        @param raw_spark_job_path: full filepath for the extraction spark job.
        @param task_group: BaseTaskGroup.
        @return: dict
        """
        raw_task_groups = {}
        for table_name, sheet_details in google_files:
            sheet_details["raw_table_name"] = table_name

            raw_task_group = task_group.build_raw_task_group_for_single_table(
                source=dag_name,
                table_name=table_name,
                target_database_base_name=schema,
                extraction_spark_job_file=raw_spark_job_path,
                raw_spark_job_extra_args=[
                    schema,
                    table_name,
                    json.dumps(sheet_details),
                    self.dag_name,
                    self.credentials_key,
                    self.credentials_scope,
                ],
                pool=task_pool,
                has_hive_sync=self.has_hive_sync,
            )
            raw_task_groups[sheet_details["clean_table_name"]] = raw_task_group

        return raw_task_groups

    def _set_done_tasks(self, google_files: dict) -> Dict:
        """
        This method creates the done task for each worksheet associated with the DAG
        context. The done task is a DummyOperator that will be used to indicate that
        the gsheet was loaded or skipped, and this is the task that Mediator will consider
        as dependency for the next tables.
        @param google_files: the dict_items with the general information of the
        context sheets.
        @return: dict
        """
        done_task_groups = {}
        for table_name, sheet_details in google_files:
            clean_table_name = sheet_details["clean_table_name"]
            task_id = StringFormatter.slugify(
                f"{self.DONE_TASK_PREFIX}-{clean_table_name}"
            )

            done_task = [DummyOperator(task_id=task_id, trigger_rule="one_success")]
            done_task_groups[
                clean_table_name
            ] = DatalakeTaskGroup.format_tasks_boundaries(done_task, done_task)

        return done_task_groups
