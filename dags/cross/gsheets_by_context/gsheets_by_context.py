import json

from airflow.operators.python_operator import BranchPythonOperator
from airflow.operators.dummy_operator import DummyOperator
from airflow.utils.helpers import chain

from bietlejuice.base.airflow.dag_builders.gsheets.gsheets_factory import (
    GsheetsDAGFactory,
)
from bietlejuice.base.airflow.helpers import TaskFlowHelper
from bietlejuice.base.airflow.task_groups.datalake_task_group import DatalakeTaskGroup
from bietlejuice.services.configuration_service import ConfigurationService

SOURCE = "gsheets"
SOURCE_WITH_CONTEXT = "gsheets_by_context"
dag_factory = GsheetsDAGFactory(
    source=SOURCE, source_with_context=SOURCE_WITH_CONTEXT, task_pool="gsheets_pool"
)
DAG_CONF = ConfigurationService(dag_name=SOURCE_WITH_CONTEXT).get_config("dags")
execution_date = "{{ds}}"


def get_run_param(dag_run, param_name):
    return dag_run.conf.get(param_name) if dag_run.conf else []


def decide_branch(
    table_name, raw_task_group, dummy_task_id, bypass_update_check_list=[], **kwargs
):
    to_ingest_output_json = kwargs["ti"].xcom_pull(
        task_ids="ingested-gsheets-id-info", key="output"
    )

    to_ingest_output = json.loads(to_ingest_output_json)
    if (
        not to_ingest_output["success_run"]
        or table_name in to_ingest_output["sheets_to_be_ingested"]
        or table_name in bypass_update_check_list
    ):
        return DatalakeTaskGroup.first_tasks(raw_task_group)[0].task_id
    else:
        return dummy_task_id


for dag_context, dag_details in DAG_CONF.items():
    dag_id = f"bietlejuice.{SOURCE}.{dag_context}"

    (
        dag,
        create_cluster_task,
        load_ids_to_be_ingested_task,
        raw_task_groups,
        clean_task_groups,
        done_task_groups,
        terminate_cluster_task
    ) = dag_factory.build_dag(
        dag_context,
        dag_details,
        execution_date,
        {"get_run_param": get_run_param}
    )
    globals()[dag_id] = dag

    for gsheet in raw_task_groups:
        dummy_task_id = f"dummy-{gsheet}-run".replace("_", "-")
        dummy_task = DummyOperator(task_id=dummy_task_id)

        check_task_id = f"check-{gsheet}-should-run".replace("_", "-")
        branch_task = BranchPythonOperator(
            task_id=check_task_id,
            python_callable=decide_branch,
            retries=3,
            op_kwargs={
                "table_name": gsheet,
                "raw_task_group": raw_task_groups[gsheet],
                "dummy_task_id": dummy_task_id,
                "bypass_update_check_list": "{{ get_run_param(dag_run, 'bypass_update_check_list') }}",
            },
            provide_context=True,
        )

        chain(
            create_cluster_task,
            load_ids_to_be_ingested_task,
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
