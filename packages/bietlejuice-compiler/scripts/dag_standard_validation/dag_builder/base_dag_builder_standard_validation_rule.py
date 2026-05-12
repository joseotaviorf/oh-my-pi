from abc import ABC, abstractmethod


class BaseDagBuilderStandardValidationRule(ABC):
    """
    Base class for DAG builder standard validators.
    """

    @classmethod
    @abstractmethod
    def is_valid(dag_declaration: dict) -> bool:
        """
        Validates the DAG declaration.
        :param dag_declaration: The DAG declaration to validate.
        :return: True if the DAG declaration is valid, False otherwise.
        """
        pass

    @classmethod
    @abstractmethod
    def get_validation_name(cls) -> str:
        """
        Returns the name of the validation.
        :return: The name of the validation.
        """
        pass

    @classmethod
    @abstractmethod
    def get_validation_description(cls) -> str:
        """
        Returns the description of the validation.
        :return: The description of the validation.
        """
        pass
