from jobs.base.base_dag import BaseDAG
from jobs.base.base_test import BaseTest
from jobs.base.enum_db import EnumDb
from jobs.dags.bi.__init__ import UNIT_ECONOMICS_TEST_QUERIES_DIR
from qa_python_utils.default_logger import logger, _logger


@logger
def __build_local_dag(sub_dag_name, dag_name, schedule_interval, start_date):
    return BaseDAG.build_dag(
        '{}.{}'.format(dag_name, sub_dag_name),
        schedule_interval=schedule_interval,
        start_date=start_date,
    )


@logger
def build(sub_dag_name, dag_name, schedule_interval, start_date):
    """ Main method for building the entire Subdag """

    local_dag = __build_local_dag(sub_dag_name, dag_name, schedule_interval, start_date)
    __build_test_tasks(local_dag)

    return local_dag


def __test_raw_query(**kwargs):
    cost_dre_query = BaseTest._get_query_from_file_name(
        file_path='{}/dre_value_check.sql'.format(UNIT_ECONOMICS_TEST_QUERIES_DIR)
    )

    _return = BaseTest.test_raw_query(
        query=cost_dre_query.format(_column_value=kwargs['_column_value'], _table=kwargs['_table'],
                                    dre_category=kwargs['dre_category']),
        enum_db=kwargs['enum_db'],
        blocking=kwargs['blocking'],
        assertion=kwargs['assertion']
    )

    _logger.info('m=__test_file_query, _return={}'.format(_return))


@logger
def __build_test_tasks(local_dag):
    # FIXME: change to get_quintoandar_python_operator after testing
    test_dre_onboarding = BaseDAG.get_python_operator(
        dag=local_dag,
        task_id='TEST_DRE_onboarding',
        func_command=__test_raw_query,
        op_kwargs={'file_path': '{}/dre_onboarding.sql'.format(UNIT_ECONOMICS_TEST_QUERIES_DIR),
                   'enum_db': EnumDb.BI_ODS,
                   'assertion': None,
                   'blocking': True,
                   'dre_category': 'Back-Office (onboarding)',
                   '_column_value': 'vl_bo_onboarding',
                   '_table': 'mgmt_ops_bo_onboarding_costs'
                   }
    )

    return [test_dre_onboarding]
