from datetime import datetime

from airflow.models import DAG
from airflow.operators.python_operator import PythonOperator
from airflow.operators.subdag_operator import SubDagOperator
from jobs.dags.util import environment as env
from jobs.new_etl.growth import Growth
from qa_python_utils.default_logger import logger

env.set_airflow_var_to_local_env('BI_DW')
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')

MAIN_DAG_NAME = 'bi-growth'

# create DAG definition
main_dag = DAG(
    dag_id=MAIN_DAG_NAME,
    description='ETL Pipeline for creating Growth Model inside the DW',
    default_args={
        'owner': 'Data Team',
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 2, 15, 0, 0, 0),
    schedule_interval=env.convert_to_utc_schedule('0 6 * * *'),
    max_active_runs=1
)


@logger
def materialize_growth_measure_table_query(**kwargs):
    funnel = kwargs['funnel']
    measure = kwargs['measure']
    _filter = kwargs['filter']
    period = kwargs['period']

    growth = Growth()
    growth.drop_table('{}_{}_{}'.format(measure, _filter, period))
    growth.create_table(funnel, measure, _filter, period)


@logger
def load_fact_growth():
    Growth().load_fact()


@logger
def consolidate_with_filters(measure):
    growth = Growth()
    growth.drop_table(measure)

    consolidation_query = Growth.get_measure_all_query()
    growth.execute_command(consolidation_query.format(measure))


@logger
def consolidate_no_filters(measure):
    growth = Growth()
    growth.drop_table(measure)

    consolidation_query = Growth.get_measure_no_filters_query()
    growth.execute_command(consolidation_query.format(measure))


@logger
def consolidate_employees_no_filters(measure):
    growth = Growth()
    growth.drop_table(measure)

    consolidation_query = Growth.get_employee_all_query()
    growth.execute_command(consolidation_query.format(measure))


def get_sub_dag_operator(sub_dag_func, sub_dag_name, funnel):
    return SubDagOperator(
        subdag=sub_dag_func(MAIN_DAG_NAME, sub_dag_name, funnel, main_dag.start_date, main_dag.schedule_interval),
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


def get_no_filter_tasks(funnel, local_dag, sub_dag_name):
    all_day_task = get_python_operator(task_id='extract_{}_all_day'.format(sub_dag_name),
                                       func_command=materialize_growth_measure_table_query,
                                       dag=local_dag,
                                       op_kwargs={'funnel': funnel, 'measure': sub_dag_name, 'filter': 'all',
                                                  'period': 'day'}
                                       )

    all_week_task = get_python_operator(task_id='extract_{}_all_week'.format(sub_dag_name),
                                        func_command=materialize_growth_measure_table_query,
                                        dag=local_dag,
                                        op_kwargs={'funnel': funnel, 'measure': sub_dag_name, 'filter': 'all',
                                                   'period': 'week'}
                                        )

    all_month_task = get_python_operator(task_id='extract_{}_all_month'.format(sub_dag_name),
                                         func_command=materialize_growth_measure_table_query,
                                         dag=local_dag,
                                         op_kwargs={'funnel': funnel, 'measure': sub_dag_name, 'filter': 'all',
                                                    'period': 'month'}
                                         )

    all_year_task = get_python_operator(task_id='extract_{}_all_year'.format(sub_dag_name),
                                        func_command=materialize_growth_measure_table_query,
                                        dag=local_dag,
                                        op_kwargs={'funnel': funnel, 'measure': sub_dag_name, 'filter': 'all',
                                                   'period': 'year'}
                                        )

    return all_day_task, all_week_task, all_month_task, all_year_task


def get_filter_tasks(_filter, funnel, local_dag, sub_dag_name):
    filter_day_task = get_python_operator(task_id='extract_{}_{}_day'.format(sub_dag_name, _filter),
                                          func_command=materialize_growth_measure_table_query,
                                          dag=local_dag,
                                          op_kwargs={'funnel': funnel, 'measure': sub_dag_name, 'filter': _filter,
                                                     'period': 'day'}
                                          )

    filter_week_task = get_python_operator(task_id='extract_{}_{}_week'.format(sub_dag_name, _filter),
                                           func_command=materialize_growth_measure_table_query,
                                           dag=local_dag,
                                           op_kwargs={'funnel': funnel, 'measure': sub_dag_name, 'filter': _filter,
                                                      'period': 'week'}
                                           )

    filter_month_task = get_python_operator(task_id='extract_{}_{}_month'.format(sub_dag_name, _filter),
                                            func_command=materialize_growth_measure_table_query,
                                            dag=local_dag,
                                            op_kwargs={'funnel': funnel, 'measure': sub_dag_name, 'filter': _filter,
                                                       'period': 'month'}
                                            )

    filter_year_task = get_python_operator(task_id='extract_{}_{}_year'.format(sub_dag_name, _filter),
                                           func_command=materialize_growth_measure_table_query,
                                           dag=local_dag,
                                           op_kwargs={'funnel': funnel, 'measure': sub_dag_name, 'filter': _filter,
                                                      'period': 'year'}
                                           )

    return filter_day_task, filter_week_task, filter_month_task, filter_year_task


def sub_dag_func_no_filters(main_dag_name, sub_dag_name, funnel, start_date, schedule_interval):
    local_dag = DAG(
        '%s.%s' % (main_dag_name, sub_dag_name),
        schedule_interval=schedule_interval,
        start_date=start_date,
    )

    # all
    no_filter_tasks = get_no_filter_tasks(funnel, local_dag, sub_dag_name)

    consolidation_task = get_python_operator(task_id='consolidate',
                                             func_command=consolidate_no_filters if sub_dag_name != 'employees' else consolidate_employees_no_filters,
                                             dag=local_dag,
                                             op_kwargs={'measure': sub_dag_name}
                                             )
    consolidation_task.set_upstream([no_filter_tasks[0], no_filter_tasks[1], no_filter_tasks[2], no_filter_tasks[3]])

    return local_dag


def sub_dag_func_with_filters(main_dag_name, sub_dag_name, funnel, start_date, schedule_interval):
    local_dag = DAG(
        '%s.%s' % (main_dag_name, sub_dag_name),
        schedule_interval=schedule_interval,
        start_date=start_date,
    )

    # all
    no_filter_tasks = get_no_filter_tasks(funnel, local_dag, sub_dag_name)

    # city
    city_tasks = get_filter_tasks('city', funnel, local_dag, sub_dag_name)

    # region
    region_tasks = get_filter_tasks('region', funnel, local_dag, sub_dag_name)

    for i in range(0, 4):
        no_filter_tasks[i] >> city_tasks[i] >> region_tasks[i]

    consolidation_task = get_python_operator(task_id='consolidate',
                                             func_command=consolidate_with_filters,
                                             dag=local_dag,
                                             op_kwargs={'measure': sub_dag_name}
                                             )
    consolidation_task.set_upstream(region_tasks)

    return local_dag


# supply measures
leads_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, 'leads', 'supply')
new_listings_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, 'new_listings', 'supply')
opportunities_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, 'opportunities', 'supply')
prospects_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, 'prospects', 'supply')
qualifieds_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, 'qualifieds', 'supply')

# closing measures
ongoing_contracts_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, 'ongoing_contracts', 'closing')

# top funnel measures
engaged_users_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, 'engaged_users', 'top_funnel')
employees_sub_dag = get_sub_dag_operator(sub_dag_func_no_filters, 'employees', 'top_funnel')
ticket_resolution_sub_dag = get_sub_dag_operator(sub_dag_func_no_filters, 'ticket_resolution', 'top_funnel')
tickets_sub_dag = get_sub_dag_operator(sub_dag_func_no_filters, 'tickets', 'top_funnel')

# demand measures
approved_by_insurer_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, 'approved_by_insurer', 'demand')
documentation_sent_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, 'documentation_sent', 'demand')
offerers_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, 'offerers', 'demand')
offerers_approved_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, 'offerers_approved', 'demand')
offerers_sent_doc_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, 'offerers_sent_doc', 'demand')
offers_approved_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, 'offers_approved', 'demand')
offers_submitted_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, 'offers_submitted', 'demand')
tenant_prospects_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, 'tenant_prospects', 'demand')
tenants_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, 'tenants', 'demand')
visitors_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, 'visitors', 'demand')
visits_booked_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, 'visits_booked', 'demand')
visits_completed_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, 'visits_completed', 'demand')

fact_task = get_python_operator('load_fact_growth', load_fact_growth, main_dag)

fact_task.set_upstream([leads_sub_dag, new_listings_sub_dag, opportunities_sub_dag, prospects_sub_dag,
                        qualifieds_sub_dag, ongoing_contracts_sub_dag, engaged_users_sub_dag, employees_sub_dag,
                        ticket_resolution_sub_dag, tickets_sub_dag, approved_by_insurer_sub_dag,
                        documentation_sent_sub_dag, offerers_sub_dag, offerers_approved_sub_dag,
                        offerers_sent_doc_sub_dag, offers_approved_sub_dag, offers_submitted_sub_dag,
                        tenant_prospects_sub_dag, tenants_sub_dag, visitors_sub_dag, visits_booked_sub_dag,
                        visits_completed_sub_dag]
                       )
