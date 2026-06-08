from pathlib import Path

import pytest
from build_jiraops_mute_criteria import BuildJiraOpsMuteCriteria


class TestLoadJiraOpsMuteList:
    def test_rejects_missing_file(self, tmp_path: Path):
        # Arrange
        builder = BuildJiraOpsMuteCriteria(mute_list_path=tmp_path / "missing.yml")

        # Act / Assert
        with pytest.raises(ValueError, match="Mute list not found"):
            builder.load_jira_ops_mute_list()

    def test_rejects_unknown_top_level_keys(self, tmp_path: Path):
        # Arrange
        path = tmp_path / "jiraops_mute_list.yml"
        path.write_text(
            "Extra:\n  equals:\n    - x\nDAG: {}\nTask: {}\nDAGOwner: {}\n",
            encoding="utf-8",
        )
        builder = BuildJiraOpsMuteCriteria(mute_list_path=path)

        # Act / Assert
        with pytest.raises(ValueError, match="Unknown Jira Ops mute list keys"):
            builder.load_jira_ops_mute_list()

    def test_rejects_non_mapping_root(self, tmp_path: Path):
        # Arrange
        path = tmp_path / "jiraops_mute_list.yml"
        path.write_text("- item\n", encoding="utf-8")
        builder = BuildJiraOpsMuteCriteria(mute_list_path=path)

        # Act / Assert
        with pytest.raises(ValueError, match="must be a YAML mapping"):
            builder.load_jira_ops_mute_list()


class TestBuildRoutingRuleCriteria:
    def test_builds_match_any_condition_structure(self, tmp_path: Path):
        # Arrange
        path = tmp_path / "jiraops_mute_list.yml"
        path.write_text(
            """
DAG:
  equals:
    - bietlejuice.dag_a
  contains:
    - bietlejuice.qube_
Task:
  equals:
    - bietlejuice.dag_a:load-raw-table
  contains:
    - bietlejuice.*:optimize-
DAGOwner:
  equals:
    - Data Governance
""".strip(),
            encoding="utf-8",
        )
        builder = BuildJiraOpsMuteCriteria(mute_list_path=path)

        # Act
        criteria = builder.build_routing_rule_criteria()

        # Assert
        assert criteria["type"] == "match-any-condition"
        assert len(criteria["conditions"]) == 5
        assert [condition["order"] for condition in criteria["conditions"]] == [
            0,
            1,
            2,
            3,
            4,
        ]

        first = criteria["conditions"][0]
        assert first == {
            "field": "extra-properties",
            "key": "DAG",
            "not": False,
            "operation": "equals",
            "expectedValue": "bietlejuice.dag_a",
            "order": 0,
        }

        contains_task = criteria["conditions"][3]
        assert contains_task["key"] == "Task"
        assert contains_task["operation"] == "contains"
        assert contains_task["expectedValue"] == "optimize-"

        dag_owner = criteria["conditions"][4]
        assert dag_owner["key"] == "DAGOwner"
        assert dag_owner["operation"] == "equals"

    def test_maps_global_task_to_task_key(self, tmp_path: Path):
        # Arrange
        path = tmp_path / "jiraops_mute_list.yml"
        path.write_text(
            """
Task:
  equals:
    - bietlejuice.*:terminate-cluster
DAG: {}
DAGOwner: {}
""".strip(),
            encoding="utf-8",
        )
        builder = BuildJiraOpsMuteCriteria(mute_list_path=path)

        # Act
        criteria = builder.build_routing_rule_criteria()
        condition = criteria["conditions"][0]

        # Assert
        assert condition["key"] == "Task"
        assert condition["expectedValue"] == "terminate-cluster"

    def test_maps_dag_specific_task_to_task_path(self, tmp_path: Path):
        # Arrange
        path = tmp_path / "jiraops_mute_list.yml"
        path.write_text(
            """
Task:
  equals:
    - bietlejuice.retsuko_fast_lane:load-clean-entry-partitioned
DAG: {}
DAGOwner: {}
""".strip(),
            encoding="utf-8",
        )
        builder = BuildJiraOpsMuteCriteria(mute_list_path=path)

        # Act
        criteria = builder.build_routing_rule_criteria()
        condition = criteria["conditions"][0]

        # Assert
        assert condition["key"] == "TaskPath"
        assert condition["expectedValue"] == (
            "bietlejuice.retsuko_fast_lane:load-clean-entry-partitioned"
        )

    def test_preserves_key_order(self, tmp_path: Path):
        # Arrange
        path = tmp_path / "jiraops_mute_list.yml"
        path.write_text(
            """
DAGOwner:
  equals:
    - Data Governance
DAG:
  equals:
    - bietlejuice.only_dag
Task: {}
""".strip(),
            encoding="utf-8",
        )
        builder = BuildJiraOpsMuteCriteria(mute_list_path=path)

        # Act
        criteria = builder.build_routing_rule_criteria()
        keys = [condition["key"] for condition in criteria["conditions"]]

        # Assert
        assert keys == ["DAG", "DAGOwner"]
