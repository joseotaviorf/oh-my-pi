import copy
import importlib
import pathlib
import sys
import requests
from glob import glob
from inspect import isclass
from os.path import dirname
from types import ModuleType
from typing import List

from bietlejuice.base.validation_suites.executors.base_validation_suites_executor import (
    BaseValidationSuitesExecutor,
)
from bietlejuice.validation_suites import VALIDATION_SUITES_PATH


from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("IntegrationsValidator")


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
        self.error_messages = []

    @staticmethod
    def _list_validation_suites_files() -> List[str]:
        """
        Lists all the validation suites files inside
         bietlejuice/validation_suites/**/*_validation_suite.py
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
        module: ModuleType,
    ) -> List[BaseValidationSuitesExecutor]:
        """Parses and loads the *Suite classes from module"""
        validation_suites_classes = []
        for class_name in dir(module):
            if class_name.endswith("Suite") and isclass(getattr(module, class_name)):
                validation_suites_classes.append(getattr(module, class_name))

        return validation_suites_classes

    def _send_slack_errors(self):
        """Sends errors messages to slack
        :returns: flag stating if message was sent or not
        """
        response_success = True
        if self.error_messages:
            payloads_by_channels = self._build_slack_payload()
            for channel, payload in payloads_by_channels.items():
                response = requests.post(channel, json=payload)
                try:
                    response.raise_for_status()
                except Exception as e:
                    logger.warn(
                        f"m=_send_slack_errors, msg=Slack message was not sent, check the webhook url: channel:{channel}, payload:{payload}, error: {e}"
                    )
                    response_success |= False
        return response_success

    def _build_slack_payload(self):
        error_dict = {}
        for error, channel in self.error_messages:
            if channel is not None:
                msg_list = error_dict.get(channel, []) + [error]
                error_dict[channel] = msg_list
        markdown_block_template = {
            "type": "section",
            "text": {"type": "mrkdwn", "text": ""},
        }
        divider_block = {"type": "divider"}
        for channel, error_list in error_dict.items():
            payload = {"blocks": [], "unfurl_links": True}
            for error_msg in error_list:
                markdown_block = copy.deepcopy(markdown_block_template)
                markdown_block["text"]["text"] = error_msg
                payload["blocks"].extend([markdown_block, divider_block])
            error_dict[channel] = payload
        return error_dict

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

    def set_suites_have_failures(self, param, messages=None):
        """Merges previous state with new one"""
        self._suites_have_failures |= param
        if messages:
            self.error_messages.extend(messages)

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
            self.set_suites_have_failures(
                v.get_suite_validation_has_failures(),
                v.get_suite_validation_failures_messages(),
            )

        self.handle_errors()

    def handle_errors(self):
        if self.get_suites_have_failures():
            send_status = self._send_slack_errors()
            if not send_status or any(
                channel is None for _, channel in self.error_messages
            ):
                raise AssertionError(
                    "One or more validations failed! (Please, check the logs)"
                )
