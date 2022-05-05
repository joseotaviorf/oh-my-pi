from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksTerminateClusterOperator,
)
from bietlejuice.jobs.composer.base.airflow.helpers import TaskFlowHelper
from bietlejuice.jobs.composer.dags.base.datalake_task_group import DatalakeTaskGroup
from bietlejuice.jobs.composer.dags.gsheets_by_context.gsheets_factory import (
    GsheetsDAGFactory,
)
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

SOURCE = "gsheets"
SOURCE_WITH_CONTEXT = "gsheets_by_context"
dag_factory = GsheetsDAGFactory(
    source=SOURCE, source_with_context=SOURCE_WITH_CONTEXT, task_pool="gsheets_pool"
)
DAG_CONF = ConfigurationService(dag_name=SOURCE_WITH_CONTEXT).get_config("dags")

for dag_context, dag_details in DAG_CONF.items():
    dag_id = f"bietlejuice.{SOURCE}.{dag_context}"

    dag, raw_task_groups, clean_task_groups = dag_factory.build_dag(
        dag_context, dag_details
    )

    globals()[dag_id] = dag

    terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
        dag=dag, task_id="terminate-cluster"
    )

    TaskFlowHelper.chain_task_groups_via_common_table(
        raw_task_groups, clean_task_groups
    )

    terminate_cluster_task.set_upstream(
        DatalakeTaskGroup.all_last_tasks(clean_task_groups)
    )

    # Set data quality tasks if exists
    independent_tasks = DatalakeTaskGroup.all_independent_tasks(raw_task_groups)
    if independent_tasks:
        terminate_cluster_task.set_upstream(independent_tasks)
