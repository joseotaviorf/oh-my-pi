from airflow.datasets import Dataset
from typing import Union


class DatasetParser:
    @classmethod
    def parse_dict_expression_as_dataset(cls, expression: Union[dict, str]) -> Dataset:
        """
        Transform the dict expression into a Dataset object.

        For example, the following expression:
        {"any": [{"all": ["dag1:task1", "dag1:task2"]}, {"all": ["dag2:task1", "dag2:task2"]}]}

        Will be transformed into the following Dataset object:
        (Dataset("dag1:task1") & Dataset("dag1:task2")) | (Dataset("dag2:task1") & Dataset("dag2:task2"))
        """

        if not isinstance(expression, dict) and not isinstance(expression, str):
            raise ValueError(f"Invalid dataset expression type: {type(expression)}")

        if isinstance(expression, dict):
            if len(expression) != 1:
                raise ValueError(f"Invalid dataset expression: {expression}")
            key = list(expression.keys())[0]
            if key not in ["all", "any"]:
                raise ValueError(f"Invalid dataset expression key: {key}")
            if key == "all":
                return cls._apply_all_operation_between_dataset_expression_list(
                    expression[key]
                )
            elif key == "any":
                return cls._apply_any_operation_between_dataset_expression_list(
                    expression[key]
                )
        else:
            return Dataset(expression)

    @classmethod
    def _apply_all_operation_between_dataset_expression_list(
        cls, dataset_expression_list: list
    ) -> Dataset:
        """Apply the "all" operation between a list of Dataset expressions."""
        if not dataset_expression_list:
            return None

        result = None
        for dataset_expression in dataset_expression_list:
            dataset = cls.parse_dict_expression_as_dataset(dataset_expression)
            result = dataset if result is None else result & dataset

        return result

    @classmethod
    def _apply_any_operation_between_dataset_expression_list(
        cls, dataset_expression_list: list
    ) -> Dataset:
        """Apply the "any" operation between a list of Dataset expressions."""
        if not dataset_expression_list:
            return None

        result = None
        for dataset_expression in dataset_expression_list:
            dataset = cls.parse_dict_expression_as_dataset(dataset_expression)
            result = dataset if result is None else result | dataset

        return result
