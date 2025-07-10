import os

from bietlejuice.base.dependencies.dependency_generator import DependencyGenerator

mock_file_path = os.path.join(
    os.path.dirname(os.path.realpath(__file__)), "mock_dependencies.yaml"
)


class TestDependencyGenerator:
    def test_will_return_correct_dependencies(
        self, dependency_generator: DependencyGenerator
    ):
        manual_modifications = {"dag1": {"add": ["dag10:task10:first-run-of-day"]}}

        generated_dependencies = dependency_generator.generate_dependencies(
            manual_modifications
        )
        expected_dependencies = {
            "dag1": ["dag0:task0:first-run-of-day", "dag10:task10:first-run-of-day"],
            "dag2": [
                "dag0:task0:first-run-of-day",
                "dag1:task1:first-run-of-day",
                "dag4:task2:first-run-of-day",
            ],
        }

        assert generated_dependencies == expected_dependencies

    def test_replace_table_dependencies_with_tasks(
        self, dependency_generator: DependencyGenerator
    ):
        dags_tables_dependencies = {
            "dag_a": ["table_a", "table_b"],
            "dag_b": ["table_c", "table_d"],
        }

        table_to_task_mapping = {
            "table_a": [
                {"dag": "foo_dag", "full_task_name": "task_that_generated_table_a"},
                {
                    "dag": "foo_dag",
                    "full_task_name": "other_task_that_generated_table_a",
                },
            ],
            "table_b": [
                {"dag": "foo_dag", "full_task_name": "task_that_generated_table_b"}
            ],
            "table_c": [
                {"dag": "foo_dag", "full_task_name": "task_that_generated_table_c"}
            ],
            "table_d": [
                {"dag": "foo_dag", "full_task_name": "task_that_generated_table_d"}
            ],
        }

        expected_return = {
            "dag_a": [
                "task_that_generated_table_a:first-run-of-day",
                "other_task_that_generated_table_a:first-run-of-day",
                "task_that_generated_table_b:first-run-of-day",
            ],
            "dag_b": [
                "task_that_generated_table_c:first-run-of-day",
                "task_that_generated_table_d:first-run-of-day",
            ],
        }

        # act
        returned_value = dependency_generator.replace_table_dependencies_with_tasks(
            dags_tables_dependencies, table_to_task_mapping
        )

        # assert

        assert expected_return == returned_value

    def test_apply_manual_modifications_add(
        self, dependency_generator: DependencyGenerator
    ):
        # arrange
        dependencies = {"dag_1": ["foo_task"]}

        dependencies_manual_modifications = {
            "dag_1": {"add": ["task_that_will_be_added"]}
        }

        expected_value = {"dag_1": ["foo_task", "task_that_will_be_added"]}

        # act
        returned_value = dependency_generator.apply_manual_modifications(
            dependencies, dependencies_manual_modifications
        )

        # assert
        assert expected_value == returned_value

    def test_apply_manual_modifications_remove(
        self, dependency_generator: DependencyGenerator
    ):
        # arrange
        dependencies = {"dag_1": ["foo_task", "task_that_will_be_removed"]}

        dependencies_manual_modifications = {
            "dag_1": {"remove": ["task_that_will_be_removed"]}
        }

        expected_value = {"dag_1": ["foo_task"]}

        # act
        returned_value = dependency_generator.apply_manual_modifications(
            dependencies, dependencies_manual_modifications
        )

        # assert
        assert expected_value == returned_value

    def test_apply_manual_modifications_override(
        self, dependency_generator: DependencyGenerator
    ):
        # arrange
        dependencies = {"dag_1": ["foo_task, foo_task_2"]}

        dependencies_manual_modifications = {
            "dag_1": {"override": ["foo_task_overrided", "foo_task_2_overrided"]}
        }

        expected_value = {"dag_1": ["foo_task_overrided", "foo_task_2_overrided"]}

        # act
        returned_value = dependency_generator.apply_manual_modifications(
            dependencies, dependencies_manual_modifications
        )

        # assert
        assert expected_value == returned_value
