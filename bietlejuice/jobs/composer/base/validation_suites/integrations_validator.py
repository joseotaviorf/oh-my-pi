import importlib
import pathlib
import sys
from glob import glob
from inspect import isclass
from os.path import dirname
from types import ModuleType
from typing import List

from bietlejuice.jobs.composer.base.validation_suites.executors.base_validation_suites_executor import (
    BaseValidationSuitesExecutor,
)
from bietlejuice.jobs.composer.validation_suites import VALIDATION_SUITES_PATH


class IntegrationsValidator:
    """
    The Validator engine main file.
    This class is responsible for parsing all validation suites and running
     its validation methods individually.
    """

    def __init__(self):
        self._validation_suites = self.load_validation_suites()
        self.connections_auth_params = None  # Stores all connections auth params
        self._suites_have_failures = False  # Controls validations state

    @staticmethod
    def _list_validation_suites_files() -> List[str]:
        """
        Lists all the validation suites files inside
         composer/validation_suites/**/*_validation_suite.py
        """
        validation_suites_classes_pattern = (
            f"{VALIDATION_SUITES_PATH}/**/*_validation_suite.py"
        )
        validation_suites_files = glob(
            validation_suites_classes_pattern, recursive=True
        )
        return validation_suites_files

    @staticmethod
    def _import_suite_module(suite_file_path: str) -> ModuleType:
        """
        Dynamically loads the file's module into system registered modules
         and returns its reference
        """
        module_path = dirname(suite_file_path)

        # We need to append the path into the sys.paths, so its module can be
        #  found by importlib.import_module
        sys.path.append(module_path)

        # Get the module name and import it
        module_name = pathlib.Path(suite_file_path).stem
        module = importlib.import_module(module_name)

        return module

    @staticmethod
    def _load_suite_classes_from_module(
        module: ModuleType
    ) -> List[BaseValidationSuitesExecutor]:
        """ Parses and loads the *Suite classes from module """
        validation_suites_classes = []
        for class_name in dir(module):
            if class_name.endswith("Suite") and isclass(getattr(module, class_name)):
                validation_suites_classes.append(getattr(module, class_name))

        return validation_suites_classes

    def load_validation_suites(self) -> List[BaseValidationSuitesExecutor]:
        """
        Get each suite file, imports it as a python module and loads the
         suite class
        """
        all_validation_suites_classes = []
        for suite_path in self._list_validation_suites_files():
            module = self._import_suite_module(suite_path)
            validation_suites_classes = self._load_suite_classes_from_module(module)
            all_validation_suites_classes.extend(validation_suites_classes)

        return all_validation_suites_classes

    def set_suites_have_failures(self, param):
        """Merges previous state with new one"""
        self._suites_have_failures |= param

    def get_suites_have_failures(self):
        return self._suites_have_failures

    def set_connections_auth_params(self, connections_auth_params) -> None:
        self.connections_auth_params = connections_auth_params

    def get_validation_suites(self) -> List[BaseValidationSuitesExecutor]:
        return self._validation_suites

    def run_validation_suites(self) -> None:
        """
        Main method. Runs all validations from Suite classes and raises an
         error if some validation failed.
        """
        for validation_suite in self.get_validation_suites():
            v = validation_suite(auth=self.connections_auth_params)
            v.run()
            self.set_suites_have_failures(v.get_suite_validation_has_failures())

        self.raise_for_errors()

    def raise_for_errors(self):
        if self.get_suites_have_failures():
            # TODO add a specific alert in Slack
            raise AssertionError(
                "One or more validations failed! (Please, check the logs)"
            )
