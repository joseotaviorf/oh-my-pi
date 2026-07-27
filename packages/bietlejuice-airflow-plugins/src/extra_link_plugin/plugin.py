"""Airflow entry-point module for ExtraLinkPlugin.

Referenced as ``extra_link_plugin.plugin:ExtraLinkPlugin``. The plugin class is
defined before importing ``DatasetTriggerOperatorLink`` so a re-entrant entry-point
load (triggered while importing Airflow models) still finds ``ExtraLinkPlugin``.
"""

from airflow.plugins_manager import AirflowPlugin


class ExtraLinkPlugin(AirflowPlugin):
    name = "extra_link_plugin"
    operator_extra_links = []


from extra_link_plugin.dataset_trigger_link_plugin.dataset_trigger_link import (  # noqa: E402
    DatasetTriggerOperatorLink,
)

ExtraLinkPlugin.operator_extra_links = [DatasetTriggerOperatorLink()]
