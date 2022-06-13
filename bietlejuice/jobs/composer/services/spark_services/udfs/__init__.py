from bietlejuice.jobs.composer.formatters import StringFormatter
from bietlejuice.jobs.composer.services.spark_services.udfs.fintech import FintechUDFs

USER_DEFINED_FUNCTIONS = {
    "SF_REMOVE_ACCENTUATION": StringFormatter.replace_accents,
    "SF_ALPHANUMERIC_SNAKE_CASE": StringFormatter.set_alphanumeric_snake_case,
    "FINTECHOPS_WORK_MIN_SLA": FintechUDFs.fintechops_work_min_sla,
}
