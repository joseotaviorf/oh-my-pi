#!/usr/bin/env python
# Airflow wrapper that allows setting the log level through the
# AIRFLOW__CORE__LOG_LEVEL environment variable and configures a Sentry handler
# if SENTRY_DSN is set. Use SENTRY_ENVIRONMENT to configure the environment.
#
# NOTE logging should change on 1.9:
#   https://github.com/apache/incubator-airflow/commit/3c3a65a3fe2edbd7eee1d736735194a1ca14962a
#
# Consider updating the Airflow installation to make use of the new logging.

import os
import logging

from airflow import conf
from airflow.bin.cli import CLIFactory, scheduler
from airflow.exceptions import AirflowConfigException
from airflow.settings import LOG_FORMAT, configure_logging


def custom_logging(app=''):
    try:
        level = conf.get('core', 'log_level')
    except AirflowConfigException:
        level = logging.INFO

    logging.getLogger().setLevel(level)

    if os.environ.get('SENTRY_DSN'):
        from raven.base import Client
        from raven.handlers.logging import SentryHandler
        from raven.conf import setup_logging

        logging.info('Initializing Sentry integration')

        client = Client(
            environment=os.environ.get('SENTRY_ENVIRONMENT'),
            dsn=os.environ.get('SENTRY_DSN'),
            tags={'app': app})

        setup_logging(SentryHandler(client, level=logging.WARNING))
        logging.info('Sentry integration is running')


def configure_logging_wrapper(log_format=LOG_FORMAT):
    configure_logging(log_format=LOG_FORMAT)
    custom_logging(app='webserver')


def scheduler_wrapper(args):
    custom_logging(app='scheduler')
    scheduler(args)


def main():
    import airflow.settings
    import airflow.bin.cli

    # monkey patching webserver's configure_logging and scheduler
    airflow.settings.configure_logging = configure_logging_wrapper
    airflow.bin.cli.scheduler = scheduler_wrapper

    # call the airflow cli to start it
    parser = CLIFactory.get_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == '__main__':
    """
    Call this script instead of airflow, e.g.:

        python airflow_wrapper.py webserver -p 8080
        python airflow_wrapper.py scheduler
    """

    main()
