from jobs.base.base_dag import BaseDAG
from jobs.base.base_etl import BaseETL
from jobs.base.base_test import BaseTest
from jobs.base.enum_db import EnumDb
from jobs.dags.bi.__init__ import DATALAKE_RAW_TEST_QUERIES_DIR
from jobs.dags.bi.__init__ import ODS_TEST_QUERIES_DIR
from jobs.dags.bi.sorting_hat.__init__ import SORTINGHAT_TEST_QUERIES_DIR
from qa_python_utils.default_logger import logger, _logger

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
    sh_query = BaseETL.get_query_from_file_name(kwargs['sh_file_path'])
    dl_query = BaseETL.get_query_from_file_name(kwargs['dl_file_path'])
    ods_query = BaseETL.get_query_from_file_name(kwargs['ods_file_path'])

    sh_return = BaseTest.get_query_result_for_comparison(
        query=sh_query,
        enum_db=EnumDb.QuintoAndar_sortinghat
    )[1][0] if sh_query != '' else None

    dl_return = BaseTest.get_query_result_for_comparison(
        query=dl_query,
        from_athena=True
    ).values[0][0] if dl_query != '' else None

    ods_return = BaseTest.get_query_result_for_comparison(
        query=ods_query,
        enum_db=EnumDb.BI_ODS
    )[1][0] if ods_query != '' else None

    if (sh_return is not None and dl_return is not None and sh_return != dl_return) \
            or (sh_return is not None and ods_return is not None and sh_return != ods_return) \
            or (dl_return is not None and dl_return is not None and dl_return != ods_return):
        raise Exception

    _logger.info('m=__test_count, msg=counts are all equal')


@logger
def __build_test_tasks(local_dag, entity):
    # FIXME: change to get_quintoandar_python_operator after testing
    test_entity_count = BaseDAG.get_python_operator(
        dag=local_dag,
        task_id='TEST_{}_count'.format(entity),
        func_command=__test_count,
        op_kwargs={
            'sh_file_path': '{}/{}_{}'.format(SORTINGHAT_TEST_QUERIES_DIR, entity, COUNT_CHECK_SQL_SUFFIX),
            'dl_file_path': '{}/{}_{}'.format(DATALAKE_RAW_TEST_QUERIES_DIR, entity, COUNT_CHECK_SQL_SUFFIX),
            'ods_file_path': '{}/{}_{}'.format(ODS_TEST_QUERIES_DIR, entity, COUNT_CHECK_SQL_SUFFIX),
        }
    )

    return test_entity_count
