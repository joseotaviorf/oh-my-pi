from pathlib import Path

import pytest

from scripts.jiraops.jiraops_enum import JiraOpsEnum
from scripts.jiraops.validate_jiraops_routine_exceptions import (
    JiraOpsRoutineExceptionsValidator,
)


def _governance(**overrides: str) -> dict[str, str]:
    base = {
        "reason": "Documented business reason for the mute.",
        "deadline": "Never",
        "created_by": "owner@quintoandar.com.br",
        "approved_by": "approver@quintoandar.com.br",
    }
    base.update(overrides)
    return base


class TestValidateRoutineExceptionsFile:
    def test_rejects_unknown_operation(self):
        # Arrange
        validator = JiraOpsRoutineExceptionsValidator(
            routine_exceptions={
                "DAG": {"startswith": {"bietlejuice.foo_": _governance()}}
            }
        )

        # Act
        errors = validator.validate_routine_exceptions()

        # Assert
        assert any("unknown operation" in error for error in errors)

    def test_rejects_missing_required_field(self):
        # Arrange
        validator = JiraOpsRoutineExceptionsValidator(
            routine_exceptions={
                "DAG": {
                    "contains": {
                        "bietlejuice.foo_": {
                            "reason": "Because.",
                            "deadline": "Never",
                            "created_by": "a@quintoandar.com.br",
                        }
                    }
                }
            }
        )

        # Act
        errors = validator.validate_routine_exceptions()

        # Assert
        assert any("approved_by" in error for error in errors)

    def test_rejects_invalid_deadline(self):
        # Arrange
        validator = JiraOpsRoutineExceptionsValidator(
            routine_exceptions={
                "DAG": {
                    "contains": {"bietlejuice.foo_": _governance(deadline="31-12-2026")}
                }
            }
        )

        # Act
        errors = validator.validate_routine_exceptions()

        # Assert
        assert any("deadline" in error and "YYYY-MM-DD" in error for error in errors)

    def test_accepts_never_and_iso_date(self):
        # Arrange
        validator = JiraOpsRoutineExceptionsValidator(
            routine_exceptions={
                "DAG": {
                    "contains": {
                        "bietlejuice.foo_": _governance(deadline="Never"),
                        "bietlejuice.bar_": _governance(deadline="2026-12-31"),
                    }
                }
            }
        )

        # Act
        errors = validator.validate_routine_exceptions()

        # Assert
        assert errors == []


class TestCollectDagOwners:
    def test_collects_owner_from_declaration(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ):
        # Arrange
        dags_root = tmp_path / "dags"
        (dags_root / "people" / "my_dag").mkdir(parents=True)
        (dags_root / "people" / "my_dag" / "my_dag_declaration.yml").write_text(
            "dag:\n  name: my_dag\n  owner: Data People\n",
            encoding="utf-8",
        )
        monkeypatch.setattr(
            "scripts.jiraops.validate_jiraops_routine_exceptions.DAG_PACKAGES_ROOT",
            str(dags_root),
        )

        # Act
        owners = JiraOpsRoutineExceptionsValidator.collect_dag_owners()

        # Assert
        assert owners == {"my_dag": "Data People"}


class TestBuildTaskUpstreamDags:
    def test_maps_task_to_upstream_dag_short_names(self):
        # Arrange
        deps = {"bietlejuice.downstream": ["bietlejuice.upstream_dag:load-raw"]}

        # Act
        mapping = JiraOpsRoutineExceptionsValidator.build_task_upstream_dags(
            deps, "bietlejuice."
        )

        # Assert
        assert mapping == {"load-raw": {"upstream_dag"}}


class TestRoutineExceptionsIntegration:
    def test_upstream_dag_allowed_with_exception(self, validator_factory):
        from scripts.dependency_handling.validate_dependencies_exist import (
            build_dependency_graph,
        )

        # Arrange
        graph = build_dependency_graph(
            {"bietlejuice.downstream": ["bietlejuice.blocked_dag:load-raw"]}
        )
        validator = validator_factory(
            {
                "DAG": {"equals": ["bietlejuice.blocked_dag"]},
                "Task": {},
                "DAGOwner": {},
            },
            dag_names={"blocked_dag"},
            routine_exceptions={
                "DAG": {"equals": {"bietlejuice.blocked_dag": _governance()}}
            },
        )
        validator.dependency_graph = graph

        # Act
        validator._check_dependencies("DAG", "equals", "bietlejuice.blocked_dag")

        # Assert
        assert validator.errors == []

    def test_upstream_dag_rejected_without_exception(self, validator_factory):
        from scripts.dependency_handling.validate_dependencies_exist import (
            build_dependency_graph,
        )

        # Arrange
        graph = build_dependency_graph(
            {"bietlejuice.downstream": ["bietlejuice.blocked_dag:load-raw"]}
        )
        validator = validator_factory(
            {"DAG": {}, "Task": {}, "DAGOwner": {}},
            dag_names={"blocked_dag"},
        )
        validator.dependency_graph = graph

        # Act
        validator._check_dependencies("DAG", "equals", "bietlejuice.blocked_dag")

        # Assert
        assert any("dependencies.yaml" in error for error in validator.errors)

    def test_dag_owner_in_mute_list_requires_exception(self, validator_factory):
        # Arrange
        validator = validator_factory(
            {
                "DAG": {},
                "Task": {},
                "DAGOwner": {"equals": ["Data Governance"]},
            }
        )

        # Act
        errors = (
            validator.routine_exceptions_validator.check_dag_owners_require_exception(
                validator.mute_list
            )
        )

        # Assert
        assert any("Data Governance" in error for error in errors)
        assert any("jiraops_mute_list_exceptions.yml" in error for error in errors)

    def test_dag_owner_passes_when_exception_documented(self, validator_factory):
        # Arrange
        validator = validator_factory(
            {
                "DAG": {},
                "Task": {},
                "DAGOwner": {"equals": ["Data Governance"]},
            },
            routine_exceptions={
                "DAGOwner": {"equals": {"Data Governance": _governance()}}
            },
        )

        # Act
        errors = (
            validator.routine_exceptions_validator.check_dag_owners_require_exception(
                validator.mute_list
            )
        )

        # Assert
        assert errors == []


def test_repo_routine_exceptions_file_is_valid():
    # Arrange
    validator = JiraOpsRoutineExceptionsValidator()

    # Act
    errors = validator.validate_routine_exceptions()

    # Assert
    assert errors == [], (
        f"Expected valid {JiraOpsEnum.JIRA_OPS_ROUTINE_EXCEPTIONS_PATH.value.name}, "
        f"got: {errors}"
    )
