from jobs.base.base_dag import BaseDAG
from jobs.base.base_test import BaseTest
from jobs.base.enum_db import EnumDb
from jobs.dags.bi.__init__ import UNIT_ECONOMICS_TEST_QUERIES_DIR
from qa_python_utils.default_logger import logger, _logger

DRE_VALUE_CHECK_SQL = 'dre_value_check.sql'

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


def __test_query(**kwargs):
    cost_dre_query = BaseTest._get_query_from_file_name(
        file_path='{}/dre_value_check.sql'.format(UNIT_ECONOMICS_TEST_QUERIES_DIR)
    )

    _return = BaseTest.test_raw_query(
        query=cost_dre_query.format(_column_value=kwargs['_column_value'], dre_category=kwargs['dre_category'],
                                    unacceptable_diff=0.02 if 'unacceptable_diff' not in kwargs else kwargs['unacceptable_diff']),
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
        func_command=__test_query,
        op_kwargs={'file_path': '{}/{}'.format(UNIT_ECONOMICS_TEST_QUERIES_DIR, DRE_VALUE_CHECK_SQL),
                   'enum_db': EnumDb.BI_ODS,
                   'assertion': None,
                   'blocking': True,
                   'dre_category': 'Back-Office (onboarding)',
                   '_column_value': 'vl_bo_onboarding'
                   }
    )

    test_dre_offboarding = BaseDAG.get_python_operator(
        dag=local_dag,
        task_id='TEST_DRE_offboarding',
        func_command=__test_query,
        op_kwargs={'file_path': '{}/{}'.format(UNIT_ECONOMICS_TEST_QUERIES_DIR, DRE_VALUE_CHECK_SQL),
                   'enum_db': EnumDb.BI_ODS,
                   'assertion': None,
                   'blocking': True,
                   'dre_category': 'Back-Office (offboarding)',
                   '_column_value': 'vl_bo_offboarding'
                   }
    )

    test_dre_ongoing = BaseDAG.get_python_operator(
        dag=local_dag,
        task_id='TEST_DRE_ongoing',
        func_command=__test_query,
        op_kwargs={'file_path': '{}/{}'.format(UNIT_ECONOMICS_TEST_QUERIES_DIR, DRE_VALUE_CHECK_SQL),
                   'enum_db': EnumDb.BI_ODS,
                   'assertion': None,
                   'blocking': True,
                   'dre_category': 'Back-Office (ongoing)',
                   '_column_value': 'vl_bo_ongoing'
                   }
    )

    test_dre_cs_post_sale = BaseDAG.get_python_operator(
        dag=local_dag,
        task_id='TEST_DRE_cs_post_sale',
        func_command=__test_query,
        op_kwargs={'file_path': '{}/{}'.format(UNIT_ECONOMICS_TEST_QUERIES_DIR, DRE_VALUE_CHECK_SQL),
                   'enum_db': EnumDb.BI_ODS,
                   'assertion': None,
                   'blocking': True,
                   'dre_category': 'Customer Support (post-sale)',
                   '_column_value': 'vl_cs_post_sale',
                   'unacceptable_diff': 0.08
                   }
    )

    test_dre_inside_sales = BaseDAG.get_python_operator(
        dag=local_dag,
        task_id='TEST_DRE_inside_sales',
        func_command=__test_query,
        op_kwargs={'file_path': '{}/{}'.format(UNIT_ECONOMICS_TEST_QUERIES_DIR, DRE_VALUE_CHECK_SQL),
                   'enum_db': EnumDb.BI_ODS,
                   'assertion': None,
                   'blocking': True,
                   'dre_category': 'Inside sales',
                   '_column_value': 'vl_inside_sales'
                   }
    )

    test_dre_collection = BaseDAG.get_python_operator(
        dag=local_dag,
        task_id='TEST_DRE_collection',
        func_command=__test_query,
        op_kwargs={'file_path': '{}/{}'.format(UNIT_ECONOMICS_TEST_QUERIES_DIR, DRE_VALUE_CHECK_SQL),
                   'enum_db': EnumDb.BI_ODS,
                   'assertion': None,
                   'blocking': True,
                   'dre_category': 'Collection',
                   '_column_value': 'vl_collection',
                   'unacceptable_diff': 0.04
                   }
    )

    test_dre_bo_pre_sale = BaseDAG.get_python_operator(
        dag=local_dag,
        task_id='TEST_DRE_bo_pre_sale',
        func_command=__test_query,
        op_kwargs={'file_path': '{}/{}'.format(UNIT_ECONOMICS_TEST_QUERIES_DIR, DRE_VALUE_CHECK_SQL),
                   'enum_db': EnumDb.BI_ODS,
                   'assertion': None,
                   'blocking': True,
                   'dre_category': 'Back-Office (pre-sale)',
                   '_column_value': 'vl_bo_pre_sale'
                   }
    )

    test_dre_listing_photos = BaseDAG.get_python_operator(
        dag=local_dag,
        task_id='TEST_DRE_listing_photos',
        func_command=__test_query,
        op_kwargs={'file_path': '{}/{}'.format(UNIT_ECONOMICS_TEST_QUERIES_DIR, DRE_VALUE_CHECK_SQL),
                   'enum_db': EnumDb.BI_ODS,
                   'assertion': None,
                   'blocking': True,
                   'dre_category': 'Listing Photos',
                   '_column_value': 'vl_photos'
                   }
    )

    test_dre_field_operations = BaseDAG.get_python_operator(
        dag=local_dag,
        task_id='TEST_DRE_field_ops',
        func_command=__test_query,
        op_kwargs={'file_path': '{}/{}'.format(UNIT_ECONOMICS_TEST_QUERIES_DIR, DRE_VALUE_CHECK_SQL),
                   'enum_db': EnumDb.BI_ODS,
                   'assertion': None,
                   'blocking': True,
                   'dre_category': 'Field Operations',
                   '_column_value': 'vl_field_ops'
                   }
    )

    return [test_dre_onboarding, test_dre_offboarding, test_dre_ongoing, test_dre_cs_post_sale, test_dre_inside_sales,
            test_dre_collection, test_dre_bo_pre_sale, test_dre_listing_photos,
            test_dre_field_operations]
