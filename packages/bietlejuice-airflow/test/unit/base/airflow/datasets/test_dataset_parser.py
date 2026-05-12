import pytest
from airflow.datasets import Dataset, DatasetAll, DatasetAny

from bietlejuice.base.airflow.datasets.dataset_parser import DatasetParser


class TestDatasetParser:
    def test_passing_not_a_string_or_dict_as_parameter_should_raise_error(self):
        with pytest.raises(ValueError):
            DatasetParser.parse_dict_expression_as_dataset(1)

    def test_passing_a_dict_with_multiple_keys_as_parameter_should_raise_error(self):
        with pytest.raises(ValueError):
            DatasetParser.parse_dict_expression_as_dataset({"all": [], "any": []})

    def test_passing_a_dict_with_an_invalid_key_as_parameter_should_raise_error(self):
        with pytest.raises(ValueError):
            DatasetParser.parse_dict_expression_as_dataset({"invalid": []})

    def test_passing_a_string_should_return_a_simple_dataset(self):
        dataset = DatasetParser.parse_dict_expression_as_dataset("dag:task")
        assert dataset == Dataset("dag:task")

    def test_passing_a_dict_with_any_should_apply_or_operator_between_datasets(self):
        dataset = DatasetParser.parse_dict_expression_as_dataset(
            {"any": ["dag1:task1", "dag1:task2", "dag1:task3"]}
        )
        assert isinstance(dataset, DatasetAny)
        assert dataset.objects == [
            Dataset("dag1:task1"),
            Dataset("dag1:task2"),
            Dataset("dag1:task3"),
        ]

    def test_passing_a_dict_with_all_should_apply_and_operator_between_datasets(self):
        dataset = DatasetParser.parse_dict_expression_as_dataset(
            {"all": ["dag1:task1", "dag1:task2", "dag1:task3"]}
        )
        assert isinstance(dataset, DatasetAll)
        assert dataset.objects == [
            Dataset("dag1:task1"),
            Dataset("dag1:task2"),
            Dataset("dag1:task3"),
        ]

    def test_should_parse_complex_expressions_recursively(self):
        dataset = DatasetParser.parse_dict_expression_as_dataset(
            {
                "any": [
                    {"all": ["dag1:task1", "dag1:task2"]},
                    {"all": ["dag2:task1", "dag2:task2"]},
                ]
            }
        )
        assert isinstance(dataset, DatasetAny)
        assert len(dataset.objects) == 2
        assert isinstance(dataset.objects[0], DatasetAll)
        assert dataset.objects[0].objects == [
            Dataset("dag1:task1"),
            Dataset("dag1:task2"),
        ]
        assert isinstance(dataset.objects[1], DatasetAll)
        assert dataset.objects[1].objects == [
            Dataset("dag2:task1"),
            Dataset("dag2:task2"),
        ]
