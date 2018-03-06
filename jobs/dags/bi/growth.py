from datetime import datetime

from airflow.models import DAG
from airflow.operators.python_operator import PythonOperator
from airflow.operators.subdag_operator import SubDagOperator
from jobs.dags.bi.base_dag import BaseDAG
from jobs.dags.util import environment as env
from jobs.new_etl.amplitude.engaged_users import EngagedUsers
from jobs.new_etl.growth.incurred import Growth
from jobs.new_etl.growth.prediction import GrowthPrediction
from qa_python_utils.default_logger import logger, _logger

env.set_airflow_var_to_local_env('BI_DW')
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')

MAIN_DAG_NAME = 'bi-growth'

# create DAG definition
main_dag = BaseDAG.build_dag(
    dag_id=MAIN_DAG_NAME,
    description='ETL Pipeline for creating Growth Model inside the DW',
    start_date=datetime(2018, 2, 15, 0, 0, 0),
    schedule_interval=env.convert_to_utc_schedule('0 6 * * *'),
    orientation='TB'
)

growth = Growth()
growth_prediction = GrowthPrediction()


@logger
def materialize_engaged_users_table_query(**kwargs):
    _filter = kwargs['filter']

    engaged_users = EngagedUsers(bucket)
    engaged_users.append_to_table(_filter=_filter)


@logger
def truncate_engaged_users_table():
    EngagedUsers.truncate_table()


@logger
def materialize_growth_measure_table_query(**kwargs):
    funnel = kwargs['funnel']
    measure = kwargs['measure']
    _filter = kwargs['filter']
    period = kwargs['period']

    growth.drop_table(table_name='{}_{}_{}'.format(measure, _filter, period), schema=Growth.SCHEMA)
    growth.create_table(funnel, measure, _filter, period)


def materialize_growth_measure_prediction_table_query(**kwargs):
    _logger.info('m=materialize_growth_measure_prediction_table_query, kwargs={}'.format(kwargs))

    funnel = kwargs['funnel']
    measure = kwargs['measure']
    _filter = kwargs['filter']
    period = kwargs['period']
    placeholders = kwargs['placeholders']

    growth_prediction.drop_table(
        table_name='prediction_{}_{}_{}'.format(measure, _filter, period),
        schema=GrowthPrediction.SCHEMA
    )
    growth_prediction.create_table(funnel, measure, _filter, period, placeholders)


@logger
def get_visits_booked_placeholders():
    return GrowthPrediction.get_visits_booked_placeholders()


@logger
def load_fact_growth():
    Growth().load_fact()


@logger
def consolidate_with_filters(measure):
    growth.drop_table(table_name=measure, schema=Growth.SCHEMA)

    consolidation_query = Growth.get_measure_all_query()
    growth.execute_command(consolidation_query.format(measure))


@logger
def consolidate_no_filters(measure):
    growth.drop_table(table_name=measure, schema=Growth.SCHEMA)

    consolidation_query = Growth.get_measure_no_filters_query()
    growth.execute_command(consolidation_query.format(measure))


@logger
def consolidate_employees_no_filters(measure):
    growth.drop_table(table_name=measure, schema=Growth.SCHEMA)

    consolidation_query = Growth.get_employee_all_query()
    growth.execute_command(consolidation_query.format(measure))


def get_sub_dag_operator(sub_dag_func, materialize_func, sub_dag_name, funnel=None, placeholders=None):
    return SubDagOperator(
        subdag=sub_dag_func(MAIN_DAG_NAME, sub_dag_name, funnel, main_dag.start_date, main_dag.schedule_interval,
                            materialize_func, placeholders),
        task_id=sub_dag_name,
        dag=main_dag,
    )


def get_python_operator(task_id, func_command, dag, op_kwargs=None):
    return PythonOperator(
        dag=dag,
        task_id=task_id,
        python_callable=func_command,
        op_kwargs=op_kwargs
    )


def get_no_filter_tasks(funnel, local_dag, sub_dag_name, materialize_func, placeholders=None):
    all_day_task = None

    if sub_dag_name != 'employees':
        all_day_task = get_python_operator(task_id='extract_{}_all_day'.format(sub_dag_name),
                                           func_command=materialize_func,
                                           dag=local_dag,
                                           op_kwargs={'funnel': funnel, 'measure': sub_dag_name, 'filter': 'all',
                                                      'period': 'day', 'placeholders': placeholders}
                                           )

    all_week_task = get_python_operator(task_id='extract_{}_all_week'.format(sub_dag_name),
                                        func_command=materialize_func,
                                        dag=local_dag,
                                        op_kwargs={'funnel': funnel, 'measure': sub_dag_name, 'filter': 'all',
                                                   'period': 'week', 'placeholders': placeholders}
                                        )

    all_month_task = get_python_operator(task_id='extract_{}_all_month'.format(sub_dag_name),
                                         func_command=materialize_func,
                                         dag=local_dag,
                                         op_kwargs={'funnel': funnel, 'measure': sub_dag_name, 'filter': 'all',
                                                    'period': 'month', 'placeholders': placeholders}
                                         )

    all_year_task = get_python_operator(task_id='extract_{}_all_year'.format(sub_dag_name),
                                        func_command=materialize_func,
                                        dag=local_dag,
                                        op_kwargs={'funnel': funnel, 'measure': sub_dag_name, 'filter': 'all',
                                                   'period': 'year', 'placeholders': placeholders}
                                        )

    return all_day_task, all_week_task, all_month_task, all_year_task


def get_filter_tasks(_filter, funnel, local_dag, sub_dag_name, materialize_func, placeholders):
    filter_day_task = get_python_operator(task_id='extract_{}_{}_day'.format(sub_dag_name, _filter),
                                          func_command=materialize_func,
                                          dag=local_dag,
                                          op_kwargs={'funnel': funnel, 'measure': sub_dag_name, 'filter': _filter,
                                                     'period': 'day', 'placeholders': placeholders}
                                          )

    filter_week_task = get_python_operator(task_id='extract_{}_{}_week'.format(sub_dag_name, _filter),
                                           func_command=materialize_func,
                                           dag=local_dag,
                                           op_kwargs={'funnel': funnel, 'measure': sub_dag_name, 'filter': _filter,
                                                      'period': 'week', 'placeholders': placeholders}
                                           )

    filter_month_task = get_python_operator(task_id='extract_{}_{}_month'.format(sub_dag_name, _filter),
                                            func_command=materialize_func,
                                            dag=local_dag,
                                            op_kwargs={'funnel': funnel, 'measure': sub_dag_name, 'filter': _filter,
                                                       'period': 'month', 'placeholders': placeholders}
                                            )

    filter_year_task = get_python_operator(task_id='extract_{}_{}_year'.format(sub_dag_name, _filter),
                                           func_command=materialize_func,
                                           dag=local_dag,
                                           op_kwargs={'funnel': funnel, 'measure': sub_dag_name, 'filter': _filter,
                                                      'period': 'year', 'placeholders': placeholders}
                                           )

    return filter_day_task, filter_week_task, filter_month_task, filter_year_task


def sub_dag_func_no_filters(main_dag_name, sub_dag_name, funnel, start_date, schedule_interval, materialize_func,
                            placeholders=None):
    local_dag = DAG(
        '{}.{}'.format(main_dag_name, sub_dag_name),
        schedule_interval=schedule_interval,
        start_date=start_date,
    )

    # all
    no_filter_tasks = get_no_filter_tasks(funnel, local_dag, sub_dag_name, materialize_func, placeholders)

    consolidation_task = get_python_operator(task_id='consolidate',
                                             func_command=consolidate_no_filters if sub_dag_name != 'employees' else consolidate_employees_no_filters,
                                             dag=local_dag,
                                             op_kwargs={'measure': sub_dag_name}
                                             )

    no_filter_list = [no_filter_tasks[i] for i in range(0, 4)]
    consolidation_task.set_upstream(no_filter_list[1:] if sub_dag_name == 'employees' else no_filter_list)

    return local_dag


def sub_dag_func_with_filters(main_dag_name, sub_dag_name, funnel, start_date, schedule_interval, materialize_func,
                              placeholders):
    local_dag = DAG(
        '{}.{}'.format(main_dag_name, sub_dag_name),
        schedule_interval=schedule_interval,
        start_date=start_date,
    )

    # all
    no_filter_tasks = get_no_filter_tasks(funnel, local_dag, sub_dag_name, materialize_func, placeholders)

    # city
    city_tasks = get_filter_tasks('city', funnel, local_dag, sub_dag_name, materialize_func, placeholders)

    # region
    region_tasks = get_filter_tasks('region', funnel, local_dag, sub_dag_name, materialize_func, placeholders)

    for i in range(0, 4):
        no_filter_tasks[i] >> city_tasks[i] >> region_tasks[i]

    consolidation_task = get_python_operator(task_id='consolidate',
                                             func_command=consolidate_with_filters,
                                             dag=local_dag,
                                             op_kwargs={'measure': sub_dag_name}
                                             )
    consolidation_task.set_upstream(region_tasks)

    return local_dag


def sub_dag_func_engaged_users(main_dag_name, sub_dag_name, funnel, start_date, schedule_interval,
                               materialize_func=None, placeholders=None):
    local_dag = DAG(
        '{}.{}'.format(main_dag_name, sub_dag_name),
        schedule_interval=schedule_interval,
        start_date=start_date,
    )

    engaged_users_truncate_task = get_python_operator('truncate_table', truncate_engaged_users_table, local_dag)

    engaged_users_all_task = get_python_operator('extract_all_data', materialize_engaged_users_table_query, local_dag,
                                                 op_kwargs={'filter': 'all'})
    engaged_users_city_task = get_python_operator('extract_city_data', materialize_engaged_users_table_query, local_dag,
                                                  op_kwargs={'filter': 'city'})
    engaged_users_region_task = get_python_operator('extract_region_data', materialize_engaged_users_table_query,
                                                    local_dag,
                                                    op_kwargs={'filter': 'region'})

    # must be sequential because of the appending operation
    engaged_users_truncate_task >> engaged_users_all_task >> engaged_users_city_task >> engaged_users_region_task

    return local_dag


# supply measures
leads_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, materialize_growth_measure_table_query, 'leads',
                                     'supply')
new_listings_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, materialize_growth_measure_table_query,
                                            'new_listings', 'supply')
opportunities_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, materialize_growth_measure_table_query,
                                             'opportunities', 'supply')
prospects_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, materialize_growth_measure_table_query, 'prospects',
                                         'supply')
qualifieds_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, materialize_growth_measure_table_query,
                                          'qualifieds', 'supply')

# closing measures
ongoing_contracts_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, materialize_growth_measure_table_query,
                                                 'ongoing_contracts', 'closing')

# top funnel measures

# Amplitude engaged users
amplitude_engaged_users_previous_task = get_sub_dag_operator(sub_dag_func_engaged_users,
                                                             None,
                                                             'amplitude_engaged_users_previous',
                                                             'top_funnel')
engaged_users_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, materialize_growth_measure_table_query,
                                             'engaged_users', 'top_funnel')
employees_sub_dag = get_sub_dag_operator(sub_dag_func_no_filters, materialize_growth_measure_table_query, 'employees',
                                         'top_funnel')
ticket_resolution_sub_dag = get_sub_dag_operator(sub_dag_func_no_filters, materialize_growth_measure_table_query,
                                                 'ticket_resolution', 'top_funnel')
tickets_sub_dag = get_sub_dag_operator(sub_dag_func_no_filters, materialize_growth_measure_table_query, 'tickets',
                                       'top_funnel')

# demand measures
approved_by_insurer_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, materialize_growth_measure_table_query,
                                                   'approved_by_insurer', 'demand')
documentation_sent_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, materialize_growth_measure_table_query,
                                                  'documentation_sent', 'demand')
offerers_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, materialize_growth_measure_table_query, 'offerers',
                                        'demand')
offerers_approved_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, materialize_growth_measure_table_query,
                                                 'offerers_approved', 'demand')
offerers_sent_doc_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, materialize_growth_measure_table_query,
                                                 'offerers_sent_doc', 'demand')
offers_approved_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, materialize_growth_measure_table_query,
                                               'offers_approved', 'demand')
offers_submitted_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, materialize_growth_measure_table_query,
                                                'offers_submitted', 'demand')
tenant_prospects_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, materialize_growth_measure_table_query,
                                                'tenant_prospects', 'demand')
tenants_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, materialize_growth_measure_table_query, 'tenants',
                                       'demand')
visitors_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, materialize_growth_measure_table_query, 'visitors',
                                        'demand')
visits_booked_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, materialize_growth_measure_table_query,
                                             'visits_booked', 'demand')
visits_completed_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, materialize_growth_measure_table_query,
                                                'visits_completed', 'demand')

# fact
fact_task = get_python_operator('load_fact_growth', load_fact_growth, main_dag)

# predictions

# demand measures
prediction_visits_booked_sub_dag = get_sub_dag_operator(sub_dag_func=sub_dag_func_with_filters,
                                                        materialize_func=materialize_growth_measure_prediction_table_query,
                                                        sub_dag_name='prediction_visits_booked',
                                                        funnel='demand',
                                                        placeholders=get_visits_booked_placeholders()
                                                        )

# flow
amplitude_engaged_users_previous_task >> engaged_users_sub_dag

leads_sub_dag >> new_listings_sub_dag >> opportunities_sub_dag >> prospects_sub_dag >> qualifieds_sub_dag >> \
ongoing_contracts_sub_dag >> engaged_users_sub_dag >> employees_sub_dag >> ticket_resolution_sub_dag >> \
tickets_sub_dag >> approved_by_insurer_sub_dag >> documentation_sent_sub_dag >> offerers_sub_dag >> \
offerers_approved_sub_dag >> offerers_sent_doc_sub_dag >> offers_approved_sub_dag >> \
offers_submitted_sub_dag >> tenant_prospects_sub_dag >> tenants_sub_dag >> visitors_sub_dag >> \
visits_booked_sub_dag >> visits_completed_sub_dag >> fact_task

fact_task.set_downstream([prediction_visits_booked_sub_dag])
