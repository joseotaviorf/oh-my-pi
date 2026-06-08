from pathlib import Path

import pytest
from build_jiraops_mute_criteria import BuildJiraOpsMuteCriteria
from validate_jiraops_routine_mute_list import JiraOpsRoutineMuteListValidator

from scripts.dependency_handling.validate_dependencies_exist import (
    DependencyGraph,
    build_dependency_graph,
)
from scripts.jiraops.jiraops_enum import JiraOpsEnum
from scripts.jiraops.validate_jiraops_routine_exceptions import (
    JiraOpsRoutineExceptionsValidator,
)


def _minimal_validator() -> JiraOpsRoutineMuteListValidator:
    validator = JiraOpsRoutineMuteListValidator.__new__(JiraOpsRoutineMuteListValidator)
    validator.expected_extra_property_keys = (
        JiraOpsEnum.JIRA_OPS_EXTRA_PROPERTY_KEYS.value
    )
    validator.allowed_operations = JiraOpsEnum.ALLOWED_OPERATIONS.value
    validator.contains_suffixes = JiraOpsEnum.CONTAINS_SUFFIXES.value
    validator.dag_id_prefix = JiraOpsEnum.DAG_ID_PREFIX.value
    validator.task_name_pattern = JiraOpsEnum._TASK_NAME_PATTERN.value
    validator.built_task_prefixes = JiraOpsEnum._BUILT_TASK_PREFIXES.value
    validator.errors = []
    validator.dag_names = set()
    validator.routine_exceptions_validator = JiraOpsRoutineExceptionsValidator(
        routine_exceptions={}
    )
    return validator


class TestCheckKeys:
    def test_rejects_unknown_top_level_keys(self):
        # Arrange
        validator = _minimal_validator()
        mute_list = {"Extra": {}, "DAG": {}, "Task": {}, "DAGOwner": {}}

        # Act
        errors = validator._check_keys(mute_list)

        # Assert
        assert any("Unknown keys" in error for error in errors)

    def test_rejects_unknown_operation(self):
        # Arrange
        validator = _minimal_validator()
        mute_list = {
            "DAG": {"startswith": ["bietlejuice.foo_"]},
            "Task": {},
            "DAGOwner": {},
        }

        # Act
        errors = validator._check_keys(mute_list)

        # Assert
        assert any("unknown operation" in error for error in errors)
        assert "startswith" in errors[0]

    def test_rejects_non_dict_property_block(self):
        # Arrange
        validator = _minimal_validator()
        mute_list = {"DAG": ["bietlejuice.foo"], "Task": {}, "DAGOwner": {}}

        # Act
        errors = validator._check_keys(mute_list)

        # Assert
        assert any("must be a dictionary" in error for error in errors)

    def test_rejects_empty_string_values(self):
        # Arrange
        validator = _minimal_validator()
        mute_list = {
            "DAG": {"equals": ["  "]},
            "Task": {},
            "DAGOwner": {},
        }

        # Act
        errors = validator._check_keys(mute_list)

        # Assert
        assert any("empty value is not allowed" in error for error in errors)


class TestCheckDuplicates:
    def test_rejects_duplicate_across_keys(self):
        # Arrange
        validator = _minimal_validator()
        mute_list = {
            "DAG": {"equals": ["bietlejuice.same_dag"]},
            "Task": {"equals": ["bietlejuice.same_dag"]},
            "DAGOwner": {},
        }

        # Act
        errors = validator._check_duplicates(mute_list)

        # Assert
        assert any("duplicate criterion" in error for error in errors)


class TestIsValidValue:
    def test_contains_must_end_with_underscore_or_hyphen(self, validator_factory):
        # Arrange
        validator = validator_factory(
            {
                "DAG": {"contains": ["bietlejuice.a"]},
                "Task": {"contains": ["optimize-"]},
                "DAGOwner": {},
            }
        )

        # Act
        dag_valid = validator._is_valid_value("DAG", "contains", "bietlejuice.a")
        task_valid = validator._is_valid_value("Task", "contains", "optimize-")

        # Assert
        assert dag_valid is False
        assert task_valid is True
        assert any("must end with" in error for error in validator.errors)

    def test_accepts_valid_contains_suffixes(self, validator_factory):
        # Arrange
        validator = validator_factory({"DAG": {}, "Task": {}, "DAGOwner": {}})

        # Act
        dag_valid = validator._is_valid_value("DAG", "contains", "zendesk_")
        task_valid = validator._is_valid_value("Task", "contains", "optimize-")

        # Assert
        assert dag_valid is True
        assert task_valid is True
        assert validator.errors == []


class TestDagNamePatterns:
    def test_equals_requires_existing_dag(self, validator_factory):
        # Arrange
        validator = validator_factory(
            {
                "DAG": {"equals": ["bietlejuice.missing_dag"]},
                "Task": {},
                "DAGOwner": {},
            },
            dag_names={"existing_dag"},
        )

        # Act
        is_valid = validator._check_dag_name_pattern(
            "equals", "bietlejuice.missing_dag"
        )

        # Assert
        assert is_valid is False
        assert any("not found in dags/" in error for error in validator.errors)

    def test_equals_accepts_existing_dag(self, validator_factory):
        # Arrange
        validator = validator_factory(
            {"DAG": {}, "Task": {}, "DAGOwner": {}},
            dag_names={"existing_dag"},
        )

        # Act
        is_valid = validator._check_dag_name_pattern(
            "equals", "bietlejuice.existing_dag"
        )

        # Assert
        assert is_valid is True

    def test_contains_requires_matching_prefix(self, validator_factory):
        # Arrange
        validator = validator_factory(
            {"DAG": {}, "Task": {}, "DAGOwner": {}},
            dag_names={"qube_metrics", "qube_dimensions"},
        )

        # Act
        is_valid = validator._check_dag_name_pattern("contains", "bietlejuice.qube_")

        # Assert
        assert is_valid is True

    def test_contains_fails_when_no_dag_matches(self, validator_factory):
        # Arrange
        validator = validator_factory(
            {"DAG": {}, "Task": {}, "DAGOwner": {}},
            dag_names={"other_dag"},
        )

        # Act
        is_valid = validator._check_dag_name_pattern("contains", "bietlejuice.qube_")

        # Assert
        assert is_valid is False
        assert any(
            "prefix" in error and "not found" in error for error in validator.errors
        )

    def test_dag_name_from_dag_id_strips_prefix(self, validator_factory):
        # Arrange
        validator = validator_factory({"DAG": {}, "Task": {}, "DAGOwner": {}})

        # Act
        dag_name = validator._dag_name_from_dag_id("bietlejuice.my_dag")

        # Assert
        assert dag_name == "my_dag"


class TestTaskNamePatterns:
    def test_accepts_global_cluster_task(self, validator_factory):
        # Arrange
        validator = validator_factory(
            {"DAG": {}, "Task": {}, "DAGOwner": {}},
            dag_names={"retsuko"},
        )

        # Act
        is_valid = validator._check_task_criterion(
            "equals", "bietlejuice.*:terminate-cluster"
        )

        # Assert
        assert is_valid is True

    def test_rejects_bare_general_task(self, validator_factory):
        # Arrange
        validator = validator_factory({"DAG": {}, "Task": {}, "DAGOwner": {}})

        # Act
        is_valid = validator._check_task_criterion("equals", "terminate-cluster")

        # Assert
        assert is_valid is False
        assert any("bietlejuice.*" in error for error in validator.errors)

    def test_rejects_pipeline_task_without_dag(self, validator_factory):
        # Arrange
        validator = validator_factory({"DAG": {}, "Task": {}, "DAGOwner": {}})

        # Act
        is_valid = validator._check_task_criterion(
            "equals", "load-clean-entry-partitioned"
        )

        # Assert
        assert is_valid is False
        assert any("bietlejuice.<dag>" in error for error in validator.errors)

    def test_accepts_dag_specific_pipeline_task(self, validator_factory):
        # Arrange
        validator = validator_factory(
            {"DAG": {}, "Task": {}, "DAGOwner": {}},
            dag_names={"retsuko_fast_lane"},
        )

        # Act
        is_valid = validator._check_task_criterion(
            "equals", "bietlejuice.retsuko_fast_lane:load-clean-entry-partitioned"
        )

        # Assert
        assert is_valid is True

    def test_accepts_global_task_prefix_in_contains(self, validator_factory):
        # Arrange
        validator = validator_factory({"DAG": {}, "Task": {}, "DAGOwner": {}})

        # Act
        is_valid = validator._check_task_criterion(
            "contains", "bietlejuice.*:optimize-"
        )

        # Assert
        assert is_valid is True

    def test_rejects_pipeline_prefix_in_contains(self, validator_factory):
        # Arrange
        validator = validator_factory({"DAG": {}, "Task": {}, "DAGOwner": {}})

        # Act
        is_valid = validator._check_task_criterion(
            "contains", "bietlejuice.*:load-clean-"
        )

        # Assert
        assert is_valid is False
        assert any(
            "cannot be muted via contains" in error for error in validator.errors
        )


class TestDependencies:
    def test_rejects_dag_that_is_upstream_of_another_dag(self, validator_factory):
        # Arrange
        graph = build_dependency_graph(
            {"bietlejuice.downstream": ["bietlejuice.blocked_dag:load-raw"]}
        )
        validator = validator_factory(
            {"DAG": {}, "Task": {}, "DAGOwner": {}},
            dag_names={"blocked_dag", "downstream"},
        )
        validator.dependency_graph = graph

        # Act
        validator._check_dependencies("DAG", "equals", "bietlejuice.blocked_dag")

        # Assert
        assert any("dependencies.yaml" in error for error in validator.errors)

    def test_allows_dag_that_only_declares_its_own_dependencies(
        self, validator_factory
    ):
        # Arrange
        graph = build_dependency_graph(
            {"bietlejuice.downstream": ["bietlejuice.blocked_dag:load-raw"]}
        )
        validator = validator_factory(
            {"DAG": {}, "Task": {}, "DAGOwner": {}},
            dag_names={"downstream"},
        )
        validator.dependency_graph = graph

        # Act
        validator._check_dependencies("DAG", "equals", "bietlejuice.downstream")

        # Assert
        assert validator.errors == []

    def test_rejects_contains_prefix_matching_upstream_dag(self, validator_factory):
        # Arrange
        graph = build_dependency_graph(
            {"bietlejuice.consumer": ["bietlejuice.qube_metrics:load-raw"]}
        )
        validator = validator_factory(
            {"DAG": {}, "Task": {}, "DAGOwner": {}},
            dag_names={"qube_metrics", "consumer"},
        )
        validator.dependency_graph = graph

        # Act
        validator._check_dependencies("DAG", "contains", "bietlejuice.qube_")

        # Assert
        assert any("dependencies.yaml" in error for error in validator.errors)

    def test_rejects_task_in_dependency_graph(self, validator_factory):
        # Arrange
        graph = DependencyGraph(upstream_task_ids={"load-clean-address"})
        validator = validator_factory(
            {
                "DAG": {},
                "Task": {"equals": ["bietlejuice.some_dag:load-clean-address"]},
                "DAGOwner": {},
            },
            dag_names={"some_dag"},
        )
        validator.dependency_graph = graph

        # Act
        validator._check_dependencies(
            "Task", "equals", "bietlejuice.some_dag:load-clean-address"
        )

        # Assert
        assert any("dependencies.yaml" in error for error in validator.errors)


class TestValidateMuteList:
    def test_returns_load_error_without_running_checks(
        self, monkeypatch: pytest.MonkeyPatch
    ):
        # Arrange
        class BrokenBuilder(BuildJiraOpsMuteCriteria):
            def load_jira_ops_mute_list(self):
                raise ValueError("Mute list not found: /tmp/missing.yml")

        class MockExceptionsValidator:
            def validate_routine_exceptions(self):
                return []

            def check_dag_owners_require_exception(self, _mute_list):
                return []

            def _has_special_exception(self, _key, _operation, _value):
                return False

        monkeypatch.setattr(
            "validate_jiraops_routine_mute_list.BuildJiraOpsMuteCriteria",
            BrokenBuilder,
        )
        monkeypatch.setattr(
            "validate_jiraops_routine_mute_list.JiraOpsRoutineExceptionsValidator",
            MockExceptionsValidator,
        )
        monkeypatch.setattr(
            "validate_jiraops_routine_mute_list.read_dependencies_file",
            lambda: {},
        )
        monkeypatch.setattr(
            "validate_jiraops_routine_mute_list.build_dependency_graph",
            lambda _deps: DependencyGraph(),
        )
        monkeypatch.setattr(
            "validate_jiraops_routine_mute_list.JiraOpsRoutineMuteListValidator._collect_dag_names",
            staticmethod(lambda: set()),
        )

        # Act
        errors = JiraOpsRoutineMuteListValidator().validate_mute_list()

        # Assert
        assert errors == ["Mute list not found: /tmp/missing.yml"]

    def test_accepts_minimal_valid_list(self, validator_factory, minimal_mute_list):
        # Arrange
        validator = validator_factory(minimal_mute_list)
        validator.mute_list = minimal_mute_list
        validator.errors = []

        # Act
        validator.errors.extend(validator._check_keys(minimal_mute_list))
        validator.errors.extend(validator._check_duplicates(minimal_mute_list))

        # Assert
        assert validator.errors == []

    def test_accepts_known_dag_owner(self, validator_factory):
        # Arrange
        validator = validator_factory(
            {
                "DAG": {},
                "Task": {},
                "DAGOwner": {"equals": ["Data Governance"]},
            },
            routine_exceptions={
                "DAGOwner": {
                    "equals": {
                        "Data Governance": {
                            "reason": "Governance team handles these alerts.",
                            "deadline": "Never",
                            "created_by": "owner@quintoandar.com.br",
                            "approved_by": "approver@quintoandar.com.br",
                        }
                    }
                }
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

    def test_rejects_unknown_dag_owner(self, validator_factory):
        # Arrange
        validator = validator_factory(
            {
                "DAG": {},
                "Task": {},
                "DAGOwner": {"equals": ["Not A Real Owner"]},
            }
        )
        validator.mute_list = validator.mute_list
        validator.errors = []

        # Act
        for key in validator.mute_list:
            for operation, values in validator.mute_list.get(key, {}).items():
                for value in values:
                    if key == "DAGOwner" and operation == "equals":
                        if value not in validator.valid_owners:
                            validator.errors.append(
                                f"{key}-{operation}]: {value!r} is not a DAGOwnerEnum value."
                            )

        # Assert
        assert any("DAGOwnerEnum" in error for error in validator.errors)

    def test_rejects_contains_on_dag_owner(self, validator_factory):
        # Arrange
        validator = validator_factory(
            {
                "DAG": {},
                "Task": {},
                "DAGOwner": {"contains": ["Data_"]},
            }
        )
        validator.errors = []

        # Act
        for key in validator.mute_list:
            for operation, values in validator.mute_list.get(key, {}).items():
                for value in values:
                    if key == "DAGOwner" and operation != "equals":
                        validator.errors.append(
                            f"{key}-{operation}]: operation {operation!r} is not supported for DAG owners."
                        )

        # Assert
        assert any(
            "not supported for DAG owners" in error for error in validator.errors
        )


class TestCollectDagNames:
    def test_collects_dag_from_declaration_and_python_package(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ):
        # Arrange
        dags_root = tmp_path / "dags"
        (dags_root / "growth" / "semrush_classified").mkdir(parents=True)
        (
            dags_root / "growth" / "semrush_classified" / "semrush_classified.py"
        ).write_text(
            "# dag package\n",
            encoding="utf-8",
        )
        (dags_root / "platform" / "my_dag").mkdir(parents=True)
        (dags_root / "platform" / "my_dag" / "my_dag_declaration.yml").write_text(
            "dag:\n  name: my_dag\n",
            encoding="utf-8",
        )
        monkeypatch.setattr(
            "validate_jiraops_routine_mute_list.DAG_PACKAGES_ROOT",
            str(dags_root),
        )

        # Act
        names = JiraOpsRoutineMuteListValidator._collect_dag_names()

        # Assert
        assert names == {"semrush_classified", "my_dag"}


class TestOwnerRedundancy:
    def test_dag_equals_redundant_when_owner_muted(self, validator_factory):
        # Arrange
        validator = validator_factory(
            {
                "DAG": {"equals": ["bietlejuice.people_dag"]},
                "Task": {},
                "DAGOwner": {"equals": ["Data People"]},
            },
            dag_names={"people_dag"},
        )
        validator.dag_owners = {"people_dag": "Data People"}

        # Act
        errors = validator.routine_exceptions_validator.check_criteria_redundant_with_muted_owners(
            validator.mute_list,
            validator.dag_owners,
            validator.dag_names,
            validator.dag_id_prefix,
        )

        # Assert
        assert any("redundant" in error and "DAG[equals]" in error for error in errors)

    def test_dag_equals_not_redundant_when_owner_not_muted(self, validator_factory):
        # Arrange
        validator = validator_factory(
            {
                "DAG": {"equals": ["bietlejuice.growth_dag"]},
                "Task": {},
                "DAGOwner": {"equals": ["Data People"]},
            },
            dag_names={"growth_dag"},
        )
        validator.dag_owners = {"growth_dag": "Data Growth"}

        # Act
        errors = validator.routine_exceptions_validator.check_criteria_redundant_with_muted_owners(
            validator.mute_list,
            validator.dag_owners,
            validator.dag_names,
            validator.dag_id_prefix,
        )

        # Assert
        assert errors == []

    def test_dag_contains_redundant_when_all_owners_muted(self, validator_factory):
        # Arrange
        validator = validator_factory(
            {
                "DAG": {"contains": ["bietlejuice.qube_"]},
                "Task": {},
                "DAGOwner": {"equals": ["Data DS Pricing"]},
            },
            dag_names={"qube_metrics", "qube_dimensions"},
        )
        validator.dag_owners = {
            "qube_metrics": "Data DS Pricing",
            "qube_dimensions": "Data DS Pricing",
        }

        # Act
        errors = validator.routine_exceptions_validator.check_criteria_redundant_with_muted_owners(
            validator.mute_list,
            validator.dag_owners,
            validator.dag_names,
            validator.dag_id_prefix,
        )

        # Assert
        assert any(
            "DAG[contains]" in error and "redundant" in error for error in errors
        )

    def test_task_equals_redundant_when_upstream_dags_only_muted_owners(
        self, validator_factory
    ):
        # Arrange
        validator = validator_factory(
            {
                "DAG": {},
                "Task": {"equals": ["load-raw"]},
                "DAGOwner": {"equals": ["Data People"]},
            },
        )
        validator.dag_owners = {"people_upstream": "Data People"}
        task_upstream = {"load-raw": {"people_upstream"}}

        # Act
        errors = validator.routine_exceptions_validator.check_criteria_redundant_with_muted_owners(
            validator.mute_list,
            validator.dag_owners,
            validator.dag_names,
            validator.dag_id_prefix,
            task_upstream,
        )

        # Assert
        assert any("Task[equals]" in error and "redundant" in error for error in errors)


class TestBuildJiraOpsMuteCriteriaIntegration:
    def test_load_nested_yaml(self, tmp_path: Path):
        # Arrange
        path = tmp_path / "jiraops_mute_list.yml"
        path.write_text(
            """
DAG:
  equals:
    - bietlejuice.foo
Task:
  contains:
    - optimize-
DAGOwner: {}
""".strip(),
            encoding="utf-8",
        )

        # Act
        loaded = BuildJiraOpsMuteCriteria(mute_list_path=path).load_jira_ops_mute_list()

        # Assert
        assert loaded["DAG"]["equals"] == ["bietlejuice.foo"]
        assert loaded["Task"]["contains"] == ["optimize-"]
