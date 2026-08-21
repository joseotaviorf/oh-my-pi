"""Tests for milestone strategy path → DAG mapping (workflow-type gated)."""

from __future__ import annotations

from bietlejuice.base.dependencies.file_dependency_generator import (
    FileDependencyGenerator,
)
from bietlejuice.base.dependencies.milestone_strategy_paths import (
    clear_milestone_delta_dag_cache,
    dag_folder_from_milestone_strategy_path,
    is_milestone_strategy_dir,
)


def test_dag_name_from_milestone_strategy_path(monkeypatch):
    gen = FileDependencyGenerator()
    relative = (
        "dw_agent_milestone/queries/dw/dim_agent_milestone/milestones/visit_events.sql"
    )
    monkeypatch.setattr(
        gen,
        "_get_path_without_base_or_owner",
        lambda path: relative,
    )
    monkeypatch.setattr(
        "bietlejuice.base.dependencies.file_dependency_generator.is_milestone_delta_dag",
        lambda dag: dag == "dw_agent_milestone",
    )
    assert (
        gen._dag_name_from_query_path("/fake/dags/agents/" + relative)
        == "bietlejuice.dw_agent_milestone"
    )


def test_milestones_folder_ignored_when_dag_not_milestone_delta(monkeypatch):
    gen = FileDependencyGenerator()
    relative = "some_query_dag/queries/dw/dim_foo/milestones/extra.sql"
    monkeypatch.setattr(
        gen,
        "_get_path_without_base_or_owner",
        lambda path: relative,
    )
    monkeypatch.setattr(
        "bietlejuice.base.dependencies.file_dependency_generator.is_milestone_delta_dag",
        lambda dag: False,
    )
    # Must not fall through to get_table_info_from_path (would invent dim_foo.milestones).
    assert gen._dag_name_from_query_path("/fake/dags/agents/" + relative) is None


def test_other_nested_folder_not_treated_as_milestone_strategy():
    """Future nested layouts (e.g. strategies/) must not hit the milestones gate."""
    clear_milestone_delta_dag_cache()
    path = "/repo/dags/agents/some_query_dag/queries/dw/dim_foo/strategies/extra.sql"
    assert dag_folder_from_milestone_strategy_path(path) is None


def test_dag_folder_from_strategy_path():
    clear_milestone_delta_dag_cache()
    path = (
        "/repo/dags/agents/dw_agent_milestone/queries/dw/"
        "dim_agent_milestone/milestones/visit_events.sql"
    )
    assert dag_folder_from_milestone_strategy_path(path) == "dw_agent_milestone"


def test_is_milestone_strategy_dir_is_layout_only():
    clear_milestone_delta_dag_cache()
    dir_path = "/repo/dags/agents/any_dag/queries/dw/some_table/milestones"
    assert is_milestone_strategy_dir(dir_path) is True
    assert (
        is_milestone_strategy_dir(
            "/repo/dags/agents/any_dag/queries/dw/some_table/strategies"
        )
        is False
    )
