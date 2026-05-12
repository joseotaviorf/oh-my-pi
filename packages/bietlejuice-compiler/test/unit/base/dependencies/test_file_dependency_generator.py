from unittest import mock

from bietlejuice.base.dependencies.file_dependency_generator import (
    FileDependencyGenerator,
)

DAG_PACKAGES_ROOT = "/tmp/dags"


def get_dict_from_yaml_file_side_effect(path: str) -> dict:
    path_tree = path.split("/")
    return {
        "database_name": (
            "datalake_sale_dag" if "enrich" in path_tree else "datalake_sale_dag_clean"
        ),
        "table_name": path_tree[-1].split(".")[0],
    }


class TestFileDependencyGenerator:
    def test_map_tables_to_correspondent_tasks(self):
        with (
            mock.patch(
                "bietlejuice.base.dependencies.file_dependency_generator.DAGPackagesPathService.list_artifact_file_paths",
                return_value=[
                    f"{DAG_PACKAGES_ROOT}/sale/enrich_sale_dag/metadata/enrich/table1.yml",
                    f"{DAG_PACKAGES_ROOT}/sale/sale_dag/metadata/clean/table2.yaml",
                ],
            ) as list_artifact_file_paths_mock,
            mock.patch(
                "bietlejuice.base.dependencies.file_dependency_generator.FileService.get_dict_from_yaml_file",
                side_effect=get_dict_from_yaml_file_side_effect,
            ) as get_dict_from_yaml_file_mock,
        ):
            unstandard_dags = {
                "bietlejuice.enrich_sale_dag": {
                    "custom_task_names": [
                        {
                            "task_name": "load-{slugged_table_name}-custom-{slugged_layer}-{slugged_schema}",
                            "table_name_condition_regex": ".*1",
                        }
                    ]
                }
            }
            file_dependency_generator = FileDependencyGenerator(
                unstandard_dags=unstandard_dags
            )
            mapping = file_dependency_generator.map_tables_to_correspondent_tasks()
            assert mapping == {
                "datalake_sale_dag.table1": [
                    {
                        "dag": "bietlejuice.enrich_sale_dag",
                        "full_task_name": "bietlejuice.enrich_sale_dag:load-table1-custom-enrich-sale-dag",
                    }
                ],
                "datalake_sale_dag_clean.table2": [
                    {
                        "dag": "bietlejuice.sale_dag",
                        "full_task_name": "bietlejuice.sale_dag:load-clean-table2",
                    }
                ],
            }
            list_artifact_file_paths_mock.assert_called_once_with("metadata", "**", "*")
            get_dict_from_yaml_file_mock.assert_has_calls(
                [
                    mock.call(
                        f"{DAG_PACKAGES_ROOT}/sale/enrich_sale_dag/metadata/enrich/table1.yml"
                    ),
                    mock.call(
                        f"{DAG_PACKAGES_ROOT}/sale/sale_dag/metadata/clean/table2.yaml"
                    ),
                ]
            )

    def test_table_dependencies_from_all_dags(self):
        with (
            mock.patch(
                "bietlejuice.base.dependencies.file_dependency_generator.DAGPackagesPathService.list_artifact_file_paths",
                return_value=[
                    f"{DAG_PACKAGES_ROOT}/sale/enrich_sale_dag/queries/enrich/table1.sql",
                    f"{DAG_PACKAGES_ROOT}/sale/sale_dag/queries/clean/table2.sql",
                ],
            ) as list_artifact_file_paths_mock,
            mock.patch(
                "bietlejuice.base.dependencies.file_dependency_generator.FileDependencyGenerator._find_all_tables_in_query_files",
                return_value={
                    "bietlejuice.enrich_sale_dag": ["datalake_sale_dag_clean.table2"]
                },
            ) as find_tables_mock,
        ):
            file_dependency_generator = FileDependencyGenerator()
            dependencies = file_dependency_generator.table_dependencies_from_all_dags()
            assert dependencies == {
                "bietlejuice.enrich_sale_dag": ["datalake_sale_dag_clean.table2"]
            }
            list_artifact_file_paths_mock.assert_called_once_with("query", "**", "*")
            find_tables_mock.assert_called_once_with(
                {
                    "bietlejuice.enrich_sale_dag": [
                        f"{DAG_PACKAGES_ROOT}/sale/enrich_sale_dag/queries/enrich/table1.sql"
                    ],
                    "bietlejuice.sale_dag": [
                        f"{DAG_PACKAGES_ROOT}/sale/sale_dag/queries/clean/table2.sql"
                    ],
                }
            )

    def test_exception_treatment(self):
        unstandard_dags = {"bietlejuice.gsheets.static": {"is_static": True}}
        # Below, there is a cycle in a-b-c-a.
        # Also, f depends on a static dag. That should be removed
        dependencies = {
            "b": ["a:task_1"],
            "c": ["b:task_2"],
            "a": ["c:task_3"],
            "f": ["e:task_4", "bietlejuice.gsheets.static:task_6"],
            "g": ["e:task_4", "f:task_5"],
        }

        file_dependency_generator = FileDependencyGenerator(
            unstandard_dags=unstandard_dags
        )
        new_dependencies = file_dependency_generator.treat_exceptions(dependencies)
        assert new_dependencies == {"f": ["e:task_4"], "g": ["e:task_4", "f:task_5"]}
