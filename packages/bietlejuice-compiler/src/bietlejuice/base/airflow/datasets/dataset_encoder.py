import textwrap

from airflow.datasets import BaseDataset, Dataset, DatasetAll, DatasetAny


class DatasetEncoder:
    @classmethod
    def encode_dataset_as_python_code(
        cls, dataset: BaseDataset, indent: int = 2
    ) -> str:
        """Encode the dataset as a Python code string."""

        if dataset is None:
            return "None"
        if isinstance(dataset, DatasetAny):
            return cls._encode_any_dataset_as_python_code(dataset, indent)
        elif isinstance(dataset, DatasetAll):
            return cls._encode_all_dataset_as_python_code(dataset, indent)
        elif isinstance(dataset, Dataset):
            return cls._encode_single_dataset_as_python_code(dataset)
        else:
            raise ValueError(f"Unsupported dataset type: {type(dataset)}")

    @classmethod
    def _encode_any_dataset_as_python_code(
        cls, dataset: DatasetAny, indent: int = 2
    ) -> str:
        """Encode the DatasetAny as a Python code string."""
        encoded_objects = [
            textwrap.indent(
                cls.encode_dataset_as_python_code(obj, indent), prefix=" " * indent
            )
            for obj in dataset.objects
        ]
        if indent == 0:
            joined_objects = " | ".join(encoded_objects)
            return f"({joined_objects})"
        else:
            joined_objects = " |\n".join(encoded_objects)
            return f"(\n{joined_objects}\n)"

    @classmethod
    def _encode_all_dataset_as_python_code(
        cls, dataset: DatasetAll, indent: int = 2
    ) -> str:
        """Encode the DatasetAll as a Python code string."""
        encoded_objects = [
            textwrap.indent(
                cls.encode_dataset_as_python_code(obj, indent), prefix=" " * indent
            )
            for obj in dataset.objects
        ]
        if indent == 0:
            joined_objects = " & ".join(encoded_objects)
            return f"({joined_objects})"
        else:
            joined_objects = " &\n".join(encoded_objects)
            return f"(\n{joined_objects}\n)"

    @classmethod
    def _encode_single_dataset_as_python_code(cls, dataset: Dataset) -> str:
        """Encode the Dataset as a Python code string."""
        return f'Dataset("{dataset.uri}")'
