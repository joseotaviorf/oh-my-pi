import pytest

from bietlejuice.base.dependencies.dependency_generator import DependencyGenerator


class MockDependencyGenerator(DependencyGenerator):
    def table_dependencies_from_all_dags(self) -> dict:
        return {
            "dag1": ["database1.table1", "database1.table2"],
            "dag2": ["database1.table1", "database2.table3", "database3.table4"],
        }

    def map_tables_to_correspondent_tasks(self) -> dict:
        return {
            "database1.table1": [{"dag": "dag0", "full_task_name": "dag0:task0"}],
            "database2.table3": [{"dag": "dag1", "full_task_name": "dag1:task1"}],
            "database3.table4": [{"dag": "dag4", "full_task_name": "dag4:task2"}],
        }

    def treat_exceptions(self, dependencies: dict) -> dict:
        return dependencies


@pytest.fixture()
def dependency_generator():
    return MockDependencyGenerator()
