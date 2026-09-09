from datetime import datetime

from airflow.models import DAG
from airflow.operators.empty import EmptyOperator

from bietlejuice.base.airflow.base_task_group import BaseTaskGroup
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.dw_query_workflow import (
    DWQueryWorkflow,
)
from bietlejuice.base.airflow.helpers.task_flow_helper import TaskFlowHelper


def _task(dag, task_id):
    return EmptyOperator(task_id=task_id, dag=dag)


class TestDWQueryWorkflowLoadChain:
    def test_combined_boundaries_preserve_dw_load_chain(self):
        dag = DAG(
            dag_id="test_dw_query_load_chain",
            start_date=datetime(2024, 1, 1),
            schedule=None,
        )
        load_staging = _task(dag, "load-dw-staging-fact_bar")
        load_dw = _task(dag, "load-dw-fact_bar")
        sync_dw = _task(dag, "sync-metadata-dw-fact_bar")
        load_dw >> sync_dw

        staging = {
            "fact_bar": BaseTaskGroup.format_tasks_boundaries(
                initial_tasks=[load_staging],
                final_tasks=[load_staging],
                load_chain_tasks=[load_staging],
            )
        }
        dw = {
            "fact_bar": BaseTaskGroup.format_tasks_boundaries(
                initial_tasks=[load_dw],
                final_tasks=[sync_dw],
                load_chain_tasks=[load_dw],
            )
        }

        workflow = object.__new__(DWQueryWorkflow)
        combined = workflow._get_dw_task_groups_boundaries(dw, staging)

        assert BaseTaskGroup.first_tasks(combined["fact_bar"]) == [load_staging]
        assert BaseTaskGroup.last_tasks(combined["fact_bar"]) == [sync_dw]
        assert BaseTaskGroup.load_chain_tasks(combined["fact_bar"]) == [load_dw]

    def test_inner_dep_waits_on_dw_load_not_sync(self):
        dag = DAG(
            dag_id="test_dw_inner_load_chain",
            start_date=datetime(2024, 1, 1),
            schedule=None,
        )
        load_staging_dim = _task(dag, "load-dw-staging-dim_foo")
        load_dw_dim = _task(dag, "load-dw-dim_foo")
        sync_dw_dim = _task(dag, "sync-metadata-dw-dim_foo")
        load_staging_fact = _task(dag, "load-dw-staging-fact_bar")
        terminate = _task(dag, "job-cluster-finished")
        load_dw_dim >> sync_dw_dim

        combined = {
            "dim_foo": BaseTaskGroup.format_tasks_boundaries(
                initial_tasks=[load_staging_dim],
                final_tasks=[sync_dw_dim],
                load_chain_tasks=[load_dw_dim],
            ),
            "fact_bar": BaseTaskGroup.format_tasks_boundaries(
                initial_tasks=[load_staging_fact],
                final_tasks=[load_staging_fact],
                load_chain_tasks=[load_staging_fact],
            ),
        }

        task_group = object.__new__(BaseTaskGroup)
        task_group.set_inner_dag_dependencies(
            task_flow_helper=TaskFlowHelper(),
            task_groups_boundaries=combined,
            dag_inner_dependencies={"fact_bar": ["dim_foo"]},
        )
        terminate.set_upstream(BaseTaskGroup.all_last_tasks(combined))

        assert load_staging_fact.task_id in load_dw_dim.downstream_task_ids
        assert load_staging_fact.task_id not in sync_dw_dim.downstream_task_ids
        assert terminate.task_id in sync_dw_dim.downstream_task_ids
