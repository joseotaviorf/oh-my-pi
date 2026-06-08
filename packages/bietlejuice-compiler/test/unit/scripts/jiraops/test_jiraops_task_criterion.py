import re

from scripts.jiraops.jiraops_task_criterion import (
    parse_task_criterion,
    routing_property_for_task,
    validate_task_contains,
    validate_task_equals,
)

_TASK_NAME_PATTERN = re.compile(r"^[a-z0-9][a-z0-9-]*$")
_BUILT_TASK_PREFIXES = ("load-clean-",)


class TestParseTaskCriterion:
    def test_parses_global_task_criterion(self):
        # Arrange
        raw = "bietlejuice.*:job-cluster-finished"

        # Act
        parsed = parse_task_criterion(raw)

        # Assert
        assert parsed.is_global
        assert parsed.task_id == "job-cluster-finished"

    def test_parses_dag_specific_task_criterion(self):
        # Arrange
        raw = "bietlejuice.foo:load-clean-bar"

        # Act
        parsed = parse_task_criterion(raw)

        # Assert
        assert not parsed.is_global
        assert parsed.dag_id == "bietlejuice.foo"
        assert parsed.task_id == "load-clean-bar"


class TestRoutingPropertyForTask:
    def test_global_equals_uses_task_key(self):
        # Arrange
        parsed = parse_task_criterion("bietlejuice.*:terminate-cluster")

        # Act
        key, value = routing_property_for_task(parsed, "equals")

        # Assert
        assert (key, value) == ("Task", "terminate-cluster")

    def test_dag_specific_equals_uses_task_path(self):
        # Arrange
        parsed = parse_task_criterion("bietlejuice.foo:load-clean-bar")

        # Act
        key, value = routing_property_for_task(parsed, "equals")

        # Assert
        assert (key, value) == ("TaskPath", "bietlejuice.foo:load-clean-bar")

    def test_global_contains_uses_task_key(self):
        # Arrange
        parsed = parse_task_criterion("bietlejuice.*:optimize-")

        # Act
        key, value = routing_property_for_task(parsed, "contains")

        # Assert
        assert (key, value) == ("Task", "optimize-")


class TestValidateTaskContains:
    def test_rejects_pipeline_prefix_in_global_contains(self):
        # Arrange
        raw = "bietlejuice.*:load-clean-"

        # Act
        errors = validate_task_contains(raw)

        # Assert
        assert errors
        assert any("cannot be muted via contains" in error for error in errors)


class TestValidateTaskEquals:
    def test_requires_dag_for_pipeline_tasks(self):
        # Arrange
        bare_task = "load-clean-entry-partitioned"

        # Act
        errors = validate_task_equals(
            bare_task,
            dag_names={"retsuko"},
            dag_id_prefix="bietlejuice.",
            task_name_pattern=_TASK_NAME_PATTERN,
            task_enum_values=set(),
            built_task_prefixes=_BUILT_TASK_PREFIXES,
        )

        # Assert
        assert any("bietlejuice.<dag>" in error for error in errors)
