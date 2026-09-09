from datetime import datetime

from airflow.models import DAG
from airflow.operators.empty import EmptyOperator

from bietlejuice.base.airflow.base_task_group import BaseTaskGroup
from bietlejuice.base.airflow.helpers.task_flow_helper import TaskFlowHelper


def _task(dag, task_id):
    return EmptyOperator(task_id=task_id, dag=dag)


class TestLoadChainInnerDependencies:
    def test_inner_deps_and_terminate_keep_sync_off_the_load_path(self):
        dag = DAG(
            dag_id="test_inner_load_chain",
            start_date=datetime(2024, 1, 1),
            schedule=None,
        )
        load_a = _task(dag, "load-clean-a")
        sync_a = _task(dag, "sync-metadata-clean-a")
        load_b = _task(dag, "load-clean-b")
        sync_b = _task(dag, "sync-metadata-clean-b")
        terminate = _task(dag, "terminate-cluster")
        load_a >> sync_a
        load_b >> sync_b

        groups = {
            "a": BaseTaskGroup.format_tasks_boundaries(
                initial_tasks=[load_a],
                final_tasks=[load_a, sync_a],
                load_chain_tasks=[load_a],
            ),
            "b": BaseTaskGroup.format_tasks_boundaries(
                initial_tasks=[load_b],
                final_tasks=[load_b, sync_b],
                load_chain_tasks=[load_b],
            ),
        }

        task_group = object.__new__(BaseTaskGroup)
        (
            without_inner,
            inner_aggregate,
        ) = task_group.set_inner_dag_dependencies(
            task_flow_helper=TaskFlowHelper(),
            task_groups_boundaries=groups,
            dag_inner_dependencies={"b": ["a"]},
        )
        terminate.set_upstream(
            BaseTaskGroup.all_last_tasks(without_inner)
            + BaseTaskGroup.last_tasks(inner_aggregate)
        )

        assert load_b.task_id in load_a.downstream_task_ids
        assert load_b.task_id not in sync_a.downstream_task_ids
        assert sync_a.task_id in load_a.downstream_task_ids
        assert terminate.task_id in sync_a.downstream_task_ids
        assert terminate.task_id in sync_b.downstream_task_ids

    def test_load_chain_falls_back_to_final_tasks(self):
        dag = DAG(
            dag_id="test_load_chain_fallback",
            start_date=datetime(2024, 1, 1),
            schedule=None,
        )
        load = _task(dag, "load-x")
        boundaries = BaseTaskGroup.format_tasks_boundaries(
            initial_tasks=[load],
            final_tasks=[load],
        )

        assert BaseTaskGroup.load_chain_tasks(boundaries) == [load]
