"""
Hatchling build hook: inject DAG declaration YAMLs into the wheel.

The `build/dags_yaml/` staging directory is populated by `make build`
(via rsync) before `uv build` runs. It only exists in full wheel builds,
not during editable installs (`uv sync`). By using a build hook instead
of a static `force-include` entry we avoid the FileNotFoundError that
Hatchling raises when the path is absent during `uv sync`.
"""

import os

from hatchling.builders.hooks.plugin.interface import BuildHookInterface


class CustomBuildHook(BuildHookInterface):
    def initialize(self, version: str, build_data: dict) -> None:
        dags_staging = os.path.abspath(
            os.path.join(self.root, "..", "..", "build", "dags_yaml")
        )
        if os.path.isdir(dags_staging):
            build_data["force_include"][dags_staging] = "dags"
