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


class LibraryStatus:
    """
    Utility class for the library status concept of Databricks libraries.
    Check [LibraryFullStatus docs](https://docs.databricks.com/dev-tools/api/latest/libraries.html#libraryfullstatus).
    """

    STATUSES = [
        "PENDING",
        "RESOLVING",
        "INSTALLING",
        "INSTALLED",
        "FAILED",
        "UNINSTALL_ON_RESTART",
    ]

    def __init__(self, library, status, is_library_for_all_clusters, messages=None):
        self.library = library
        self.messages = messages or []
        self.status = status
        self.is_library_for_all_clusters = is_library_for_all_clusters

    @property
    def status(self):
        return self._status

    @status.setter
    def status(self, status):
        if status not in LibraryStatus.STATUSES:
            raise DatabricksUnexpectedStateError(
                f"Unexpected library status {status} with message: {self.messages}. If the status "
                "has been introduced recently, please check the Databricks user "
                "guide for troubleshooting information."
            )
        self._status = status

    @property
    def is_terminal(self):
        return self.status in ("INSTALLED", "FAILED", "UNINSTALL_ON_RESTART")

    @property
    def is_installed(self):
        return self.status == "INSTALLED"

    def raise_for_status(self):
        """
        Raises stored :class:`DatabricksTerminalStateError`, if the status is
        terminal and unsuccessful.
        """
        if self.is_terminal and not self.is_installed:
            raise DatabricksTerminalStateError(
                f"{self.__class__.__name__} failed with "
                f"terminal status: {self.status}. "
                f"Message: {self.messages}"
            )

    def __eq__(self, other):
        return (
            self.library == other.library
            and self.status == other.status
            and self.is_library_for_all_clusters == other.is_library_for_all_clusters
        )

    def __repr__(self):
        return str(self.__dict__)
