"""Airflow UI extra-link plugin package.

Keep this module free of Airflow imports. Importing Airflow here can re-enter
the plugin manager while ``extra_link_plugin`` is still initializing (circular
import via the ``airflow.plugins`` entry point).
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

__all__ = ["ExtraLinkPlugin", "DatasetTriggerOperatorLink"]

if TYPE_CHECKING:
    from extra_link_plugin.dataset_trigger_link_plugin.dataset_trigger_link import (
        DatasetTriggerOperatorLink as DatasetTriggerOperatorLink,
    )
    from extra_link_plugin.plugin import ExtraLinkPlugin as ExtraLinkPlugin


def __getattr__(name: str) -> Any:
    if name == "ExtraLinkPlugin":
        from extra_link_plugin.plugin import ExtraLinkPlugin

        return ExtraLinkPlugin
    if name == "DatasetTriggerOperatorLink":
        from extra_link_plugin.dataset_trigger_link_plugin.dataset_trigger_link import (
            DatasetTriggerOperatorLink,
        )

        return DatasetTriggerOperatorLink
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
