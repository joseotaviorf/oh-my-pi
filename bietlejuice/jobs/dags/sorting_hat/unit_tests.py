from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.base_test import BaseTest
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.dags import DATALAKE_TEST_QUERIES_DIR, ODS_TEST_QUERIES_DIR
from bietlejuice.jobs.dags.sorting_hat import SORTINGHAT_TEST_QUERIES_DIR

COUNT_CHECK_SQL_SUFFIX = 'count_check.sql'

logger = QuintoAndarLogger('sorting-hat-unit-tests')


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
        enum_db=EnumDB.QuintoAndar_sortinghat
    )[1][0] if sh_query != '' else None

    dl_return = BaseTest.get_query_result_for_comparison(
        query=dl_query,
        from_athena=True
    ).values[0][0] if dl_query != '' else None

    ods_return = BaseTest.get_query_result_for_comparison(
        query=ods_query,
        enum_db=EnumDB.BI_ODS
    )[1][0] if ods_query != '' else None

    BaseTest.compare_sources(kwargs['acceptable_diff'], [sh_return, dl_return, ods_return])
    logger.info('m=__test_count, msg=counts are all equal')


@logger
def __build_test_tasks(local_dag, entity):
    return BaseDAG.build_python_operator(
        dag=local_dag,
        task_id='TEST_{}_count'.format(entity),
        python_callable=__test_count,
        op_kwargs={
            'sh_file_path': '{}/sorting_hat/{}_{}'.format(SORTINGHAT_TEST_QUERIES_DIR, entity, COUNT_CHECK_SQL_SUFFIX),
            'dl_file_path': '{}/sorting_hat/{}_raw_{}'.format(DATALAKE_TEST_QUERIES_DIR, entity,
                                                              COUNT_CHECK_SQL_SUFFIX),
            'ods_file_path': '{}/sorting_hat/{}_{}'.format(ODS_TEST_QUERIES_DIR, entity, COUNT_CHECK_SQL_SUFFIX),
            'acceptable_diff': .0
        }
    )
