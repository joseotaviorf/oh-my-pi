import logging
from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.etl.elasticsearch import SkynetModelLogsFetcher

logger = QuintoAndarLogger('skynet_logs_to_s3')


def ml_logs_to_s3(es_extractor=None, **kwargs):
    # required arguments
    app_name = kwargs.get('APP_NAME', "skynet")
    model_name = kwargs['MODEL_NAME']
    if es_extractor is None:
        es_logs__hostname = kwargs['ES_LOGS__HOSTNAME']
        es_extractor = SkynetModelLogsFetcher(
            es_logs__hostname=es_logs__hostname,
            model_logger_name=model_name
        )
    execution_date = kwargs['execution_date']

    # optional arguments
    logging_levels = kwargs.get(
        'LOGGING_LEVELS',
        [logging.WARNING, logging.ERROR, logging.INFO]
    )
    step_size = kwargs.get('step_size', 1000)
    max_size = kwargs.get('max_size')
    scroll = kwargs.get('scroll', '5m')

    # build base s3 key
    base_key = (
        'raw/elasticsearch/ml_logs/' +
        'app={app_name}/' +
        'model={model_name}/' +
        'logging_level={logging_level}/' +
        'dt={dt}/' +
        '{filename}.gz'
    )

    for level in logging_levels:
        level_name = logging.getLevelName(level)
        logger.info(
            'm=ml_logs_to_s3, msg=querying for {}'.format(level_name))
        logs_paginator = es_extractor.run(
            date_=execution_date,
            message_level=level_name,
            step_size=step_size,
            max_size=max_size,
            scroll=scroll
        )

        for page, log in enumerate(logs_paginator):
            key = base_key.format(
                app_name=app_name,
                model_name=model_name,
                dt=execution_date.strftime('%Y-%m-%d'),
                logging_level=level_name,
                filename='search_page_{}'.format(str(page).zfill(5))
            )

            logger.info(
                'm=ml_logs_to_s3, msg=writing file {}'.format(key))

            BaseETL().json_to_s3(
                dict_list=log['hits']['hits'],
                s3_bucket='5a-datalake',
                s3_key=key
            )
