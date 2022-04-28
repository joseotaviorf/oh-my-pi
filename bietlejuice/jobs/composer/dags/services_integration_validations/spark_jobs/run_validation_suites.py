"""
    This Spark Job executes every validation suite placed in path
     bietlejuice/jobs/composer/validation_suites/**/*_validation_suite.py
"""
import json
import logging
from json import JSONDecodeError
from typing import Dict

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import BaseDBUtils
from bietlejuice.jobs.composer.base.validation_suites.integrations_validator import (
    IntegrationsValidator,
)

JOB_NAME = "run_validation_suites"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

base_dbutils = BaseDBUtils()
if base_dbutils.get_dbutils() is not None:
    dbutils = base_dbutils.get_dbutils()


def read_databricks_secrets() -> Dict[str, Dict]:
    """
    Get each secret (mapped in the variable secret_keys) from the Databricks
     secrets.
    Unfortunately we cannot add this operation inside the bietlejuice wheel
     because it needs access the variable dbutils from the wheel's outer scope,
     therefore it is not accessible inside it.

    :return: the secret value for each key
    """
    secrets_configs = {}
    secret_keys = dbutils.secrets.list(scope="quintoandar")
    for k in secret_keys:
        conn_config_json = dbutils.secrets.get(scope="quintoandar", key=k.key)
        try:
            secrets_configs[k.key] = json.loads(conn_config_json)
        except JSONDecodeError:
            secrets_configs[k.key] = conn_config_json

    return secrets_configs


if __name__ == "__main__":
    logger.info(f"m={JOB_NAME}, msg=Running validations for all suite groups")

    integrations_validator = IntegrationsValidator()
    integrations_validator.set_connections_auth_params(
        connections_auth_params=read_databricks_secrets()
    )
    integrations_validator.run_validation_suites()

    logger.info(f"m={JOB_NAME}, msg=Validations finished")
