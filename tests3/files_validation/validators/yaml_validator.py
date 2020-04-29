from tests3.files_validation.validators.base_validator import BaseValidator
import yaml

from quintoandar_logger import QuintoAndarLogger

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
                    "m=validate_yaml_keys, rule_id={}, msg=The rule seems to be broken. Please verify fields.".format(
                        rule
                    )
                )
                return False
        return True
