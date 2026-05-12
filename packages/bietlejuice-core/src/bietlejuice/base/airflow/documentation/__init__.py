from os import path

from bietlejuice.base.airflow.documentation.cron_descriptor import CronDescriptor

__all__ = ["CronDescriptor"]

COMPOSER_DOCUMENTATION_PATH = path.dirname(path.realpath(__file__))  # TODO rename
