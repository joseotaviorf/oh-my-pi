from datetime import datetime

from airflow.models import DAG
from airflow.operators.empty import EmptyOperator

from bietlejuice.base.airflow.base_task_group import BaseTaskGroup
from bietlejuice.base.airflow.helpers.task_flow_helper import TaskFlowHelper


def _task(dag, task_id):
    return EmptyOperator(task_id=task_id, dag=dag)


class TestTaskFlowHelperLoadChain:
    def test_chain_task_groups_uses_load_chain_not_sync(self):
        dag = DAG(
            dag_id="test_chain_load_chain",
            start_date=datetime(2024, 1, 1),
            schedule=None,
        )
        load_raw = _task(dag, "load-raw-t")
        sync_raw = _task(dag, "sync-metadata-raw-t")
        load_clean = _task(dag, "load-clean-t")
        load_raw >> sync_raw

        from_groups = {
            "t": BaseTaskGroup.format_tasks_boundaries(
                initial_tasks=[load_raw],
                final_tasks=[load_raw, sync_raw],
                load_chain_tasks=[load_raw],
            )
        }
        to_groups = {
            "t": BaseTaskGroup.format_tasks_boundaries(
                initial_tasks=[load_clean],
                final_tasks=[load_clean],
            )
        }

        TaskFlowHelper.chain_task_groups_via_common_table(from_groups, to_groups)

        assert load_clean.task_id in load_raw.downstream_task_ids
        assert load_clean.task_id not in sync_raw.downstream_task_ids

    def test_cross_downstream_uses_load_chain_not_sync(self):
        dag = DAG(
            dag_id="test_cross_load_chain",
            start_date=datetime(2024, 1, 1),
            schedule=None,
        )
        load_a = _task(dag, "load-a")
        sync_a = _task(dag, "sync-metadata-a")
        load_b = _task(dag, "load-b")
        load_a >> sync_a

        from_group = BaseTaskGroup.format_tasks_boundaries(
            initial_tasks=[load_a],
            final_tasks=[load_a, sync_a],
            load_chain_tasks=[load_a],
        )
        to_group = BaseTaskGroup.format_tasks_boundaries(
            initial_tasks=[load_b],
            final_tasks=[load_b],
        )

        TaskFlowHelper().cross_downstream_task_groups(from_group, to_group)

        assert load_b.task_id in load_a.downstream_task_ids
        assert load_b.task_id not in sync_a.downstream_task_ids
        assert sync_a.task_id in load_a.downstream_task_ids
