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


class ClusterState:
    """
    Utility class for the cluster state concept of Databricks clusters.
    """

    STATES = [
        "PENDING",
        "RUNNING",
        "RESTARTING",
        "RESIZING",
        "TERMINATING",
        "TERMINATED",
        "ERROR",
        "UNKNOWN",
    ]

    def __init__(self, state, state_message):
        self.state = state
        self.state_message = state_message

    @property
    def state(self):
        return self._state

    @state.setter
    def state(self, state):
        if state not in ClusterState.STATES:
            raise DatabricksUnexpectedStateError(
                f"Unexpected cluster state: {state}. If the state has "
                "been introduced recently, please check the Databricks user "
                "guide for troubleshooting information."
            )
        self._state = state

    @property
    def is_terminal(self):
        return self.state in ("RUNNING", "TERMINATED", "ERROR", "UNKNOWN")

    @property
    def is_running(self):
        return self.state == "RUNNING"

    @property
    def is_terminated(self):
        return self.state == "TERMINATED"

    def raise_for_state(self, fail_on_terminated=True):
        """
        Raises stored :class:`DatabricksTerminalStateError`, if the state is
        terminal and unsuccessful.
        """
        if (self.is_terminal and not (self.is_running or self.is_terminated)) or (
            self.is_terminated and fail_on_terminated
        ):
            raise DatabricksTerminalStateError(
                f"{self.__class__.__name__} failed with "
                f"terminal state: {self.state}. "
                f"Message: {self.state_message}"
            )

    def __eq__(self, other):
        return self.state == other.state and self.state_message == other.state_message

    def __repr__(self):
        return str(self.__dict__)
