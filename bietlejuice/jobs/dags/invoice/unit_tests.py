from qa_python_utils.default_logger import logger, _logger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.base_test import BaseTest
from bietlejuice.jobs.base.enum_db import EnumDb
from bietlejuice.jobs.dags import DATALAKE_RAW_TEST_QUERIES_DIR, DATALAKE_CLEAN_TEST_QUERIES_DIR, ODS_TEST_QUERIES_DIR

COUNT_CHECK_SQL_SUFFIX = 'count_check.sql'


@logger
def __build_local_dag(sub_dag_name, dag_name, schedule_interval, start_date):
    return BaseDAG.build_dag(
        '{}.{}'.format(dag_name, sub_dag_name),
        schedule_interval=schedule_interval,
        start_date=start_date,
    )


@logger
def build(sub_dag_name, dag_name, schedule_interval, start_date, entity):
    """ Main method for building the entire Subdag """

    local_dag = __build_local_dag(sub_dag_name, dag_name, schedule_interval, start_date)
    __build_test_tasks(local_dag, entity)

    return local_dag


def __test_count(**kwargs):
    dl_raw_query = BaseETL.get_query_from_file_name(kwargs['dl_raw_file_path'])
    dl_clean_query = BaseETL.get_query_from_file_name(kwargs['dl_clean_file_path'])
    ods_query = BaseETL.get_query_from_file_name(kwargs['ods_file_path'])

    dl_raw_return = BaseTest.get_query_result_for_comparison(
        query=dl_raw_query,
        from_athena=True
    ).values[0][0] if dl_raw_query != '' else None

    dl_clean_return = BaseTest.get_query_result_for_comparison(
        query=dl_clean_query,
        from_athena=True
    ).values[0][0] if dl_clean_query != '' else None

    ods_return = BaseTest.get_query_result_for_comparison(
        query=ods_query,
        enum_db=EnumDb.BI_ODS
    )[1][0] if ods_query != '' else None

    BaseTest.compare_sources(kwargs['acceptable_diff'], [dl_raw_return, dl_clean_return, ods_return])
    _logger.info('m=__test_count, msg=counts are all equal')


@logger
def __build_test_tasks(local_dag, entity):
    return BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='TEST_{}_count'.format(entity),
        func_command=__test_count,
        op_kwargs={
            'dl_raw_file_path': '{}/{}_{}'.format(DATALAKE_RAW_TEST_QUERIES_DIR, entity, COUNT_CHECK_SQL_SUFFIX),
            'dl_clean_file_path': '{}/{}_{}'.format(DATALAKE_CLEAN_TEST_QUERIES_DIR, entity, COUNT_CHECK_SQL_SUFFIX),
            'ods_file_path': '{}/{}_{}'.format(ODS_TEST_QUERIES_DIR, entity, COUNT_CHECK_SQL_SUFFIX),
            'acceptable_diff': .0
        }
    )
