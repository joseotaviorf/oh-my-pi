"""Smoke imports for internalized Airflow UI plugins."""


def test_extra_link_plugin_imports():
    from extra_link_plugin import (  # noqa: F401
        DatasetTriggerOperatorLink,
        ExtraLinkPlugin,
    )
