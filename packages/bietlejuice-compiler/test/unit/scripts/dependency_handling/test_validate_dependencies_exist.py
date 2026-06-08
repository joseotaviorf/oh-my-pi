from scripts.dependency_handling.validate_dependencies_exist import (
    build_dependency_graph,
    dag_is_upstream_dependency_of_another_dag,
)


def test_dag_is_upstream_when_listed_under_another_dag():
    graph = build_dependency_graph(
        {
            "bietlejuice.downstream": ["bietlejuice.upstream_dag:load-raw"],
            "bietlejuice.upstream_only": ["bietlejuice.other:load-clean"],
        }
    )
    assert dag_is_upstream_dependency_of_another_dag("bietlejuice.upstream_dag", graph)
    assert dag_is_upstream_dependency_of_another_dag("upstream_dag", graph)


def test_dag_is_not_upstream_when_only_a_dependent_dag_key():
    graph = build_dependency_graph(
        {"bietlejuice.downstream": ["bietlejuice.upstream_dag:load-raw"]}
    )
    assert "bietlejuice.downstream" in graph.dependent_dag_names
    assert not dag_is_upstream_dependency_of_another_dag(
        "bietlejuice.downstream", graph
    )


def test_dag_upstream_without_task_suffix():
    graph = build_dependency_graph({"bietlejuice.consumer": ["bietlejuice.producer"]})
    assert dag_is_upstream_dependency_of_another_dag("bietlejuice.producer", graph)
