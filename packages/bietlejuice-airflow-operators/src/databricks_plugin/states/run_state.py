#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#

from databricks_plugin.states.errors import (
    DatabricksTerminalStateError,
    DatabricksUnexpectedStateError,
)


class RunState:
    """
    Utility class for the run state concept of Databricks runs.
    """

    RUN_LIFE_CYCLE_STATES = [
        "BLOCKED",
        "PENDING",
        "RUNNING",
        "TERMINATING",
        "TERMINATED",
        "SKIPPED",
        "INTERNAL_ERROR",
        "WAITING_FOR_RETRY",
    ]

    def __init__(
        self,
        life_cycle_state,
        state_message,
        result_state=None,
        user_cancelled_or_timedout=None,
    ):
        self.life_cycle_state = life_cycle_state
        self.state_message = state_message
        self.result_state = result_state
        self.user_cancelled_or_timedout = user_cancelled_or_timedout

    @property
    def life_cycle_state(self):
        return self._life_cycle_state

    @life_cycle_state.setter
    def life_cycle_state(self, life_cycle_state):
        if life_cycle_state not in RunState.RUN_LIFE_CYCLE_STATES:
            raise DatabricksUnexpectedStateError(
                f"Unexpected life cycle state: {life_cycle_state}. If the state has "
                "been introduced recently, please check the Databricks user "
                "guide for troubleshooting information."
            )
        self._life_cycle_state = life_cycle_state

    @property
    def is_terminal(self):
        return self.life_cycle_state in ("TERMINATED", "SKIPPED", "INTERNAL_ERROR")

    @property
    def is_successful(self):
        return self.result_state == "SUCCESS"

    def raise_for_state(self):
        """
        Raises stored :class:`DatabricksTerminalStateError`, if the state is
        terminal and unsuccessful.
        """
        if self.is_terminal and not self.is_successful:
            raise DatabricksTerminalStateError(
                f"{self.__class__.__name__} failed with "
                f"terminal state: {self.result_state}. "
                f"Message: {self.state_message}"
            )

    def __eq__(self, other):
        return (
            self.life_cycle_state == other.life_cycle_state
            and self.result_state == other.result_state
            and self.state_message == other.state_message
            and self.user_cancelled_or_timedout == self.user_cancelled_or_timedout
        )

    def __repr__(self):
        return str(self.__dict__)
