"""Validate dependencies.yaml entries exist in Airflow; build graph for other checks."""

from __future__ import annotations

from dataclasses import dataclass, field

from airflow.models import DagBag

from bietlejuice.base.dependencies.bietlejuice_dependency_helper import (
    BietlejuiceDependencyHelper,
)


@dataclass
class DependencyGraph:
    """DAGs and tasks referenced in dags/dependencies.yaml."""

    dependent_dag_names: set[str] = field(default_factory=set)
    upstream_dag_names: set[str] = field(default_factory=set)
    upstream_task_ids: set[str] = field(default_factory=set)


def read_dependencies_file() -> dict:
    return BietlejuiceDependencyHelper.read_dependencies()


def build_dependency_graph(dependencies: dict) -> DependencyGraph:
    graph = DependencyGraph()
    for dependent_dag_id, dependency_list in dependencies.items():
        graph.dependent_dag_names.add(str(dependent_dag_id))
        unique_dependencies = (
            BietlejuiceDependencyHelper.find_unique_dependencies_in_dependency_object(
                dependency_list or []
            )
        )
        for dependency in unique_dependencies:
            index_dependency_entry(dependency, graph)
    return graph


def index_dependency_entry(dependency: str, graph: DependencyGraph) -> None:
    if ":" not in dependency:
        graph.upstream_dag_names.add(dependency)
        return

    dag_id, task_id, *_schedule = dependency.split(":")
    graph.upstream_dag_names.add(dag_id)
    graph.upstream_task_ids.add(task_id)


def _dag_id_variants(dag_id: str) -> set[str]:
    """Airflow DAG ids in dependencies.yaml use the bietlejuice.* prefix."""
    dag_id = str(dag_id)
    if dag_id.startswith("bietlejuice."):
        return {dag_id, dag_id.removeprefix("bietlejuice.")}
    return {dag_id, f"bietlejuice.{dag_id}"}


def dag_is_upstream_dependency_of_another_dag(
    dag_id: str, graph: DependencyGraph
) -> bool:
    """
    True when dag_id is listed under another DAG's dependency list in dependencies.yaml.

    Structure: ``<dependent_dag>: [<upstream>, ...]``. Only upstream entries count;
    being a dependent_dag key (having its own dependencies) does not block muting.
    """
    return bool(_dag_id_variants(dag_id) & graph.upstream_dag_names)


def task_is_in_dependency_graph(task: str, graph: DependencyGraph) -> bool:
    if task in graph.upstream_task_ids:
        return True
    return any(
        upstream_task == task or upstream_task.startswith(task)
        for upstream_task in graph.upstream_task_ids
    )


def validate_dependencies_exist(dependencies: dict, dag_bag: DagBag) -> None:
    for dependent_name, dependency_list in dependencies.items():
        if dependent_name not in dag_bag.dags:
            print(f"DAG {dependent_name} not found")

        for dependency in dependency_list:
            dag_name, task_name = dependency.split(":")
            if dag_name not in dag_bag.dags:
                print(f"DAG {dag_name} not found")
                continue
            if task_name not in dag_bag.dags[dag_name].task_ids:
                print(f"Task {task_name} not found in DAG {dag_name}")
                continue


if __name__ == "__main__":
    dag_bag = DagBag(store_serialized_dags=True, include_examples=False)
    dag_bag.collect_dags_from_db()

    dependencies = read_dependencies_file()
    validate_dependencies_exist(dependencies, dag_bag)
