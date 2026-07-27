"""Parse-time entry point: register Wonka DAGs from the quintoml config registry.

Option-A prototype — see docs/prototypes/wonka_deploy_optionA.md. All logic
(and its unit tests) lives in ``bietlejuice.services.wonka_registry_service``
inside the bietlejuice-airflow package, which is installed on the Airflow
image. Kill switch: set ``WONKA_REGISTRY_ENABLED=0`` on the deployment.

This module must keep the words "airflow" and "dag" so the DAG file processor
picks it up under DAG_DISCOVERY_SAFE_MODE.
"""

from bietlejuice.services.wonka_registry_service import (
    register_wonka_dags_from_registry,
)

register_wonka_dags_from_registry(globals())
