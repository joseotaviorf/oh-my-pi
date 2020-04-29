from abc import ABC, abstractmethod


class BaseValidator(ABC):
    """
    Base validator to be extended to each file type (e.g., yaml and query files)
    """

    @abstractmethod
    def run_validator(self, validation_method):
        """
        Executes the validator method passed by the user
        :return: a boolean indicating the result of the validation
        """
        raise NotImplementedError

    @abstractmethod
    def read_file(self):
        raise NotImplementedError
