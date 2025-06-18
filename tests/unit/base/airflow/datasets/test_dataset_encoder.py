import pytest
from airflow.datasets import Dataset
from bietlejuice.base.airflow.datasets.dataset_encoder import DatasetEncoder


class TestDatasetEncoder:
    def test_passing_simple_dataset_should_return_dataset_object_string(self):
        dataset = Dataset("dataset_name")
        assert (
            DatasetEncoder.encode_dataset_as_python_code(dataset)
            == 'Dataset("dataset_name")'
        )

    def test_passing_dataset_any_should_return_or_operator_string(self):
        dataset = Dataset("dataset_name_1") | Dataset("dataset_name_2")
        assert (
            DatasetEncoder.encode_dataset_as_python_code(dataset, indent=0)
            == '(Dataset("dataset_name_1") | Dataset("dataset_name_2"))'
        )

    def test_passing_dataset_all_should_return_and_operator_string(self):
        dataset = Dataset("dataset_name_1") & Dataset("dataset_name_2")
        assert (
            DatasetEncoder.encode_dataset_as_python_code(dataset, indent=0)
            == '(Dataset("dataset_name_1") & Dataset("dataset_name_2"))'
        )

    def test_passing_complex_dataset_should_return_nested_operators_string(self):
        dataset = (Dataset("dataset_name_1") | Dataset("dataset_name_2")) & Dataset(
            "dataset_name_3"
        )
        assert (
            DatasetEncoder.encode_dataset_as_python_code(dataset, indent=0)
            == '((Dataset("dataset_name_1") | Dataset("dataset_name_2")) & Dataset("dataset_name_3"))'
        )

    def test_indentation_should_be_respected(self):
        dataset = (Dataset("dataset_name_1") | Dataset("dataset_name_2")) & Dataset(
            "dataset_name_3"
        )
        assert (
            DatasetEncoder.encode_dataset_as_python_code(dataset, indent=2)
            == """
(
  (
    Dataset("dataset_name_1") |
    Dataset("dataset_name_2")
  ) &
  Dataset("dataset_name_3")
)
""".strip()
        )

    def test_none_should_return_none_string(self):
        assert DatasetEncoder.encode_dataset_as_python_code(None) == "None"

    def test_other_data_types_should_raise_value_error(self):
        with pytest.raises(ValueError):
            DatasetEncoder.encode_dataset_as_python_code("dataset_name")
