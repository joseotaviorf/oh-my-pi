"""
This Spark Job executes every validation suite placed in path
 bietlejuice/validation_suites/**/*_validation_suite.py

Connection auth params are loaded via BaseDBUtils (Databricks secrets on DBR,
 AWS Secrets Manager facade on EMR).
"""

import json
import logging
from json import JSONDecodeError
from typing import Any, Dict

from quintoandar_logger import QuintoAndarLogger
from validations_engine.validations_engine import ValidationsEngine

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.db.database_enum import DatabaseEnum
from bietlejuice.base.notification.gchat_webhooks_enum import GchatWebhooksEnum
from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.validation_suites import VALIDATION_SUITES_PATH

JOB_NAME = "run_validation_suites"

logging.getLogger("py4j").setLevel(logging.ERROR)
logging.getLogger("py4j.java_gateway").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)
dbutils = BaseDBUtils().get_dbutils()

REQUIRED_SECRET_KEYS = (
    APIEnum.HUBSPOT,
    APIEnum.SURVICATE,
    APIEnum.MX_FACEBOOK,
    DatabaseEnum.CRM,
    DatabaseEnum.HEIMDALL,
    DatabaseEnum.CYBER,
)

OPTIONAL_SECRET_KEYS = (
    GchatWebhooksEnum.DATA_ALERTS,
    GchatWebhooksEnum.DATA_QUALITY_DEFAULT,
    GchatWebhooksEnum.DATA_QUALITY_PROD,
    GchatWebhooksEnum.DATA_QUALITY_FORNO,
)

SECRET_SCOPE = "quintoandar"


def read_connection_auth_params() -> Dict[str, Any]:
    """
    Load connection auth params from secrets for validation suites.

    Required keys must be present; optional GChat webhook keys are skipped when
    missing.

    :return: secret value for each loaded key
    """
    if dbutils is None:
        raise RuntimeError(
            f"m={JOB_NAME}, msg=dbutils is not available; cannot load connection auth params"
        )

    secrets_configs: Dict[str, Any] = {}

    for key in REQUIRED_SECRET_KEYS:
        try:
            raw = dbutils.secrets.get(scope=SECRET_SCOPE, key=key)
        except Exception as e:
            raise RuntimeError(
                f"m={JOB_NAME}, msg=required secret missing, key={key}, error={e}"
            ) from e
        try:
            secrets_configs[key] = json.loads(raw)
        except JSONDecodeError:
            secrets_configs[key] = raw

    for key in OPTIONAL_SECRET_KEYS:
        try:
            raw = dbutils.secrets.get(scope=SECRET_SCOPE, key=key)
        except Exception as e:
            logger.warning(
                f"m={JOB_NAME}, msg=optional secret missing, key={key}, error={e}"
            )
            continue
        try:
            secrets_configs[key] = json.loads(raw)
        except JSONDecodeError:
            secrets_configs[key] = raw

    return secrets_configs


if __name__ == "__main__":
    logger.info(f"m={JOB_NAME}, msg=Running validations for all suite groups")

    integrations_validator = ValidationsEngine(
        validations_suites_root_path=VALIDATION_SUITES_PATH
    )
    integrations_validator.set_connections_auth_params(
        connections_auth_params=read_connection_auth_params()
    )
    integrations_validator.run_validation_suites()

    logger.info(f"m={JOB_NAME}, msg=Validations finished")
