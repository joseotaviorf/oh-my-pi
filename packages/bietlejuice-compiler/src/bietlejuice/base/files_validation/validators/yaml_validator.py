import yaml
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.files_validation.validators.base_validator import BaseValidator

logger = QuintoAndarLogger("YAMLValidator")


class YamlValidator(BaseValidator):
    """
    Extends the BaseValidator to load and run_validator of YAML files
    """

    def __init__(self, file_path, validator_args=None):
        self.file_path = file_path
        self.validator_args = validator_args
        self.yaml = self.read_file()

    def run_validator(self, validation_method):
        """
        Executes the validator method passed by the user
        :return: a boolean indicating the result of the validation
        """
        if self.validator_args is None:
            return validation_method(self.yaml)
        return validation_method(self.yaml, self.validator_args)

    def read_file(self):
        """
        Reads the yaml file from `self.file_path`
        :return: a yaml file as a `dict`
        """
        with open(self.file_path) as stream:
            yaml_file = yaml.safe_load(stream)
        return yaml_file

    @staticmethod
    @logger
    def validate_yaml_keys(yaml_content, required_keys={}):
        """
        Validates if yaml content dict has all the required keys
        :param yaml_content: yaml file dict
        :param required_keys: required keys in yaml file
        :return: return `True` if yaml content has all required fields, otherwise `False`.
        """
        for rule in yaml_content:
            fields = set(yaml_content.get(rule))
            if required_keys.difference(fields):
                logger.error(
                    f"m=validate_yaml_keys, rule_id={rule}, msg=The rule seems to be broken. Please verify fields."
                )
                return False
        return True

    @logger
    def is_cyclic(self, dic, key, visited_keys, path):
        """
        Validates if graph defined by dict has any cycle

        :param dic: dictionary containing DAG dependencies
        :param key: dictionary's key that is being visited at the moment
        :param visited_keys: list of all the keys visited so far
        :param path: list of keys visited before the current one

        :return: True if graph has cycle. False if it doesn't.
        """
        if key in path:
            logger.error(
                f"m=is_cyclic, msg=The dependencies between the DAGs {path} are cyclical. "
                "Please, verify the yaml file"
            )
            return True

        local_path = path[:]  # avoids manipulating the same object
        local_path.append(key)

        for dependency in dic[key]:
            if (
                dic.get(dependency) is not None
                and dependency not in visited_keys
                and self.is_cyclic(dic, dependency, visited_keys, local_path)
            ):
                return True

        if key not in visited_keys:
            visited_keys.append(key)
        return False

    def validate_cyclic_dependency(self, dic):
        """
        Validates if graph defined by dict has any cycle through is_cyclic() method

        :param dic: dictionary containing DAG dependencies
        :return: True if graph has cycle. False if it doesn't.
        """
        visited_keys = []
        for key in dic:
            if key not in visited_keys and self.is_cyclic(dic, key, visited_keys, []):
                return False
        return True

    @staticmethod
    @logger
    def validate_list_dependencies(dic):
        """
        Validates if all the dependencies are lists of strings

        :param dic: dictionary containing DAG dependencies
        :return: True if all the dependencies are lists of strings. False otherwise.
        """
        for key in dic:
            if not isinstance(dic[key], list):
                logger.error(
                    f"m=validate_list_dependencies, msg=The dependencies of the DAG {key} should be a list"
                )
                return False
            for value in dic[key]:
                if not isinstance(value, str):
                    logger.error(
                        f"m=validate_list_dependencies, msg=The dependencies of the DAG {key} should be a list"
                    )
                    return False
        return True
