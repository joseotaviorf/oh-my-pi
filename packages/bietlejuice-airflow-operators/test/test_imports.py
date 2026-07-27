"""Smoke imports for internalized Databricks/EMR plugins."""


def test_databricks_plugin_imports():
    from databricks_plugin.hooks.databricks_hook import (
        QuintoAndarDatabricksHook,  # noqa: F401
    )
    from databricks_plugin.operators.create_cluster import (  # noqa: F401
        QuintoAndarDatabricksCreateClusterOperator,
    )


def test_emr_plugin_imports():
    from emr_plugin import template_translator  # noqa: F401
    from emr_plugin.operators.create_cluster import (  # noqa: F401
        QuintoAndarEmrCreateClusterOperator,
    )
