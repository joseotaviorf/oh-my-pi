from datetime import datetime

from airflow.models import DAG
from airflow.operators.python_operator import PythonOperator
from airflow.operators.subdag_operator import SubDagOperator
from qa_python_utils.default_logger import logger, _logger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl.amplitude.active_users import ActiveUsers
from bietlejuice.jobs.new_etl.amplitude.engaged_users import EngagedUsers
from bietlejuice.jobs.new_etl.amplitude.listings_unique_page_views import ListingsWithPageViews
from bietlejuice.jobs.new_etl.amplitude.owner_landing_views import OwnerLandingViews, OwnerLandingViewsBV
from bietlejuice.jobs.new_etl.amplitude.schedule_page_views import SchedulePageViews
from bietlejuice.jobs.new_etl.growth.incurred import Growth
from bietlejuice.jobs.new_etl.growth.prediction import GrowthPrediction

env.set_airflow_var_to_local_env('BI_DW')
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')

MAIN_DAG_NAME = 'bi-growth'

# create DAG definition
main_dag = DAG(
    dag_id=MAIN_DAG_NAME,
    description='ETL Pipeline for creating Growth Model inside the DW',
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=datetime(2018, 2, 15, 0, 0, 0),
    schedule_interval=env.convert_to_utc_schedule('0 6 * * *'),
    max_active_runs=1,
    catchup=False,
    orientation='TB'
)


@logger
def materialize_engaged_users_table_query(**kwargs):
    _filter = kwargs['filter']

    engaged_users = EngagedUsers(bucket)
    engaged_users.append_to_table(_filter=_filter)


@logger
def truncate_engaged_users_table():
    EngagedUsers.truncate_table()


@logger
def materialize_listings_unique_page_views_table_query(**kwargs):
    _filter = kwargs['filter']

    listings_unique_page_views = ListingsWithPageViews(bucket)
    listings_unique_page_views.append_to_table(_filter=_filter)


@logger
def truncate_listings_unique_page_views_table():
    ListingsWithPageViews.truncate_table()


@logger
def materialize_schedule_page_views_table_query(**kwargs):
    _filter = kwargs['filter']

    schedule_page_views = SchedulePageViews(bucket)
    schedule_page_views.append_to_table(_filter=_filter)


@logger
def truncate_schedule_page_views_table():
    SchedulePageViews.truncate_table()


@logger
def materialize_active_users_table_query():
    active_users = ActiveUsers(bucket)
    active_users.append_to_table(_filter='all')


@logger
def truncate_active_users_table():
    ActiveUsers.truncate_table()


@logger
def materialize_owner_landing_views_table_query():
    owner_landing_views = OwnerLandingViews(bucket)
    owner_landing_views.append_to_table(_filter='all')


@logger
def truncate_owner_landing_views_table():
    OwnerLandingViews.truncate_table()


@logger
def materialize_owner_landing_views_bv_table_query():
    owner_landing_views_bv = OwnerLandingViewsBV(bucket)
    owner_landing_views_bv.append_to_table(_filter='all')


@logger
def truncate_owner_landing_views_bv_table():
    OwnerLandingViewsBV.truncate_table()


@logger
def materialize_growth_measure_table_query(**kwargs):
    funnel = kwargs['funnel']
    measure = kwargs['measure']
    _filter = kwargs['filter']
    period = kwargs['period']

    Growth.drop_table(table_name='{}_{}_{}'.format(measure, _filter, period), schema=Growth.SCHEMA)
    Growth.create_table(funnel, measure, _filter, period)


def materialize_growth_measure_prediction_table_query(**kwargs):
    _logger.info('m=materialize_growth_measure_prediction_table_query, kwargs={}'.format(kwargs))

    funnel = kwargs['funnel']
    measure = kwargs['measure']
    _filter = kwargs['filter']
    period = kwargs['period']
    placeholders = kwargs['placeholders']

    GrowthPrediction.drop_table(
        table_name='{}_{}_{}'.format(measure, _filter, period),
        schema=GrowthPrediction.SCHEMA
    )
    GrowthPrediction.create_prediction_table(funnel, measure, _filter, period, placeholders)


@logger
def get_visits_booked_placeholders():
    return GrowthPrediction.get_visits_booked_placeholders()


@logger
def get_visits_completed_placeholders():
    return GrowthPrediction.get_visits_completed_placeholders()


@logger
def get_offers_submitted_placeholders():
    return GrowthPrediction.get_offers_submitted_placeholders()


@logger
def get_offers_approved_placeholders():
    return GrowthPrediction.get_offers_approved_placeholders()


@logger
def get_documentation_sent_placeholders():
    return GrowthPrediction.get_documentation_sent_placeholders()


@logger
def get_approved_by_insurer_placeholders():
    return GrowthPrediction.get_approved_by_insurer_placeholders()


@logger
def get_tenants_placeholders():
    return GrowthPrediction.get_tenants_placeholders()


@logger
def load_fact_growth():
    Growth().load_fact()


@logger
def append_predictions_fact_growth():
    GrowthPrediction().append_predictions_fact()


@logger
def consolidate_with_filters(measure):
    Growth.drop_table(table_name=measure, schema=Growth.SCHEMA)

    consolidation_query = Growth.get_measure_all_query()
    Growth.execute_command(consolidation_query.format(measure))


@logger
def consolidate_no_filters(measure):
    Growth.drop_table(table_name=measure, schema=Growth.SCHEMA)

    consolidation_query = Growth.get_measure_no_filters_query()
    Growth.execute_command(consolidation_query.format(measure))


@logger
def consolidate_employees_no_filters(measure):
    Growth.drop_table(table_name=measure, schema=Growth.SCHEMA)

    consolidation_query = Growth.get_employee_all_query()
    Growth.execute_command(consolidation_query.format(measure))


def get_sub_dag_operator(sub_dag_func, materialize_func, sub_dag_name, funnel=None, placeholders=None,
                         truncate_func=None):
    return SubDagOperator(
        subdag=sub_dag_func(MAIN_DAG_NAME, sub_dag_name, funnel, main_dag.start_date, main_dag.schedule_interval,
                            materialize_func, placeholders, truncate_func),
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
                            placeholders, truncate_func):
    local_dag = DAG(
        '{}.{}'.format(main_dag_name, sub_dag_name),
        schedule_interval=schedule_interval,
        start_date=start_date
    )

    # all
    no_filter_tasks = get_no_filter_tasks(funnel, local_dag, sub_dag_name, materialize_func, placeholders)

    consolidation_task = get_python_operator(task_id='consolidate',
                                             func_command=consolidate_no_filters if sub_dag_name != 'employees' else
                                             consolidate_employees_no_filters,
                                             dag=local_dag,
                                             op_kwargs={'measure': sub_dag_name}
                                             )

    no_filter_list = [no_filter_tasks[i] for i in range(0, 4)]
    consolidation_task.set_upstream(no_filter_list[1:] if sub_dag_name == 'employees' else no_filter_list)

    return local_dag


def sub_dag_func_with_filters(main_dag_name, sub_dag_name, funnel, start_date, schedule_interval, materialize_func,
                              placeholders, truncate_func):
    local_dag = DAG(
        '{}.{}'.format(main_dag_name, sub_dag_name),
        schedule_interval=schedule_interval,
        start_date=start_date
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


def sub_dag_func_amplitude(main_dag_name, sub_dag_name, funnel, start_date, schedule_interval,
                           materialize_func, placeholders, truncate_func):
    local_dag = DAG(
        '{}.{}'.format(main_dag_name, sub_dag_name),
        schedule_interval=schedule_interval,
        start_date=start_date
    )

    truncate_task = get_python_operator(
        'truncate_table',
        truncate_func,
        local_dag
    )

    all_task = get_python_operator(
        'extract_all_data',
        materialize_func,
        local_dag,
        op_kwargs={'filter': 'all'}
    )

    city_task = get_python_operator(
        'extract_city_data',
        materialize_func,
        local_dag,
        op_kwargs={'filter': 'city'}
    )

    region_task = get_python_operator(
        'extract_region_data',
        materialize_func,
        local_dag,
        op_kwargs={'filter': 'region'}
    )

    # must be sequential because of the appending operation
    truncate_task >> all_task >> city_task >> region_task

    return local_dag


def sub_dag_func_active_users(main_dag_name, sub_dag_name, funnel, start_date, schedule_interval,
                              materialize_func, placeholders, truncate_func):
    local_dag = DAG(
        '{}.{}'.format(main_dag_name, sub_dag_name),
        schedule_interval=schedule_interval,
        start_date=start_date
    )

    active_users_truncate_task = get_python_operator('truncate_table', truncate_active_users_table, local_dag)

    active_users_all_task = get_python_operator('extract_all_data', materialize_active_users_table_query, local_dag)

    # must be sequential because of the appending operation
    active_users_truncate_task >> active_users_all_task

    return local_dag


def sub_dag_func_owner_landing_views_users(main_dag_name, sub_dag_name, funnel, start_date, schedule_interval,
                                           materialize_func, placeholders, truncate_func):
    local_dag = DAG(
        '{}.{}'.format(main_dag_name, sub_dag_name),
        schedule_interval=schedule_interval,
        start_date=start_date
    )

    owner_landing_views_truncate_task = get_python_operator('truncate_table', truncate_owner_landing_views_table,
                                                            local_dag)

    owner_landing_views_all_task = get_python_operator('extract_all_data', materialize_owner_landing_views_table_query,
                                                       local_dag)

    # must be sequential because of the appending operation
    owner_landing_views_truncate_task >> owner_landing_views_all_task

    return local_dag


def sub_dag_func_owner_landing_views_bv_users(main_dag_name, sub_dag_name, funnel, start_date, schedule_interval,
                                              materialize_func, placeholders, truncate_func):
    local_dag = DAG(
        '{}.{}'.format(main_dag_name, sub_dag_name),
        schedule_interval=schedule_interval,
        start_date=start_date
    )

    owner_landing_views_bv_truncate_task = get_python_operator('truncate_table', truncate_owner_landing_views_bv_table,
                                                               local_dag)

    owner_landing_views_bv_all_task = get_python_operator('extract_all_data',
                                                          materialize_owner_landing_views_bv_table_query,
                                                          local_dag)

    # must be sequential because of the appending operation
    owner_landing_views_bv_truncate_task >> owner_landing_views_bv_all_task

    return local_dag


# supply measures
leads_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, materialize_growth_measure_table_query, 'leads',
                                     'supply')
new_listings_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, materialize_growth_measure_table_query,
                                            'new_listings', 'supply')
new_listings_landing_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, materialize_growth_measure_table_query,
                                                    'new_listings_landing', 'supply')
new_listings_landing_bv_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters,
                                                       materialize_growth_measure_table_query,
                                                       'new_listings_landing_bv', 'supply')
opportunities_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, materialize_growth_measure_table_query,
                                             'opportunities', 'supply')
prospects_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, materialize_growth_measure_table_query, 'prospects',
                                         'supply')
qualifieds_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, materialize_growth_measure_table_query,
                                          'qualifieds', 'supply')

# closing measures
ongoing_contracts_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, materialize_growth_measure_table_query,
                                                 'ongoing_contracts', 'closing')
ended_rentals_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, materialize_growth_measure_table_query,
                                             'ended_rentals', 'closing')

# top funnel measures

ongoing_listings_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, materialize_growth_measure_table_query,
                                                'ongoing_listings', 'top_funnel')

ongoing_stranded_listings_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters,
                                                         materialize_growth_measure_table_query,
                                                         'ongoing_stranded_listings', 'top_funnel')

# Amplitude engaged users
amplitude_engaged_users_previous_task = get_sub_dag_operator(sub_dag_func_amplitude,
                                                             materialize_engaged_users_table_query,
                                                             'amplitude_engaged_users_previous',
                                                             'top_funnel', None,
                                                             truncate_engaged_users_table)
engaged_users_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, materialize_growth_measure_table_query,
                                             'engaged_users', 'top_funnel', None, truncate_engaged_users_table)

# Amplitude engaged users
amplitude_listings_unique_page_views_previous_task = get_sub_dag_operator(sub_dag_func_amplitude,
                                                                          materialize_listings_unique_page_views_table_query,
                                                                          'amplitude_listings_unique_page_views_previous',
                                                                          'top_funnel', None,
                                                                          truncate_listings_unique_page_views_table)
listings_unique_page_views_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters,
                                                          materialize_growth_measure_table_query,
                                                          'listings_unique_page_views', 'top_funnel', None,
                                                          truncate_listings_unique_page_views_table)

# Amplitude schedule page views
amplitude_schedule_page_views_previous_task = get_sub_dag_operator(sub_dag_func_amplitude,
                                                                   materialize_schedule_page_views_table_query,
                                                                   'amplitude_schedule_page_views_previous',
                                                                   'top_funnel', None,
                                                                   truncate_schedule_page_views_table)
schedule_page_views_sub_dag = get_sub_dag_operator(sub_dag_func_with_filters, materialize_growth_measure_table_query,
                                                   'schedule_page_views', 'top_funnel', None,
                                                   truncate_schedule_page_views_table)

# Amplitude active users
amplitude_active_users_previous_task = get_sub_dag_operator(sub_dag_func_active_users,
                                                            None,
                                                            'amplitude_active_users_previous',
                                                            'top_funnel')
active_users_sub_dag = get_sub_dag_operator(sub_dag_func_no_filters, materialize_growth_measure_table_query,
                                            'active_users', 'top_funnel')

# Amplitude owner landing views
amplitude_owner_landing_views_previous_task = get_sub_dag_operator(sub_dag_func_owner_landing_views_users,
                                                                   None,
                                                                   'amplitude_owner_landing_views_previous',
                                                                   'top_funnel')
owner_landing_views_sub_dag = get_sub_dag_operator(sub_dag_func_no_filters, materialize_growth_measure_table_query,
                                                   'owner_landing_views', 'top_funnel')

amplitude_owner_landing_views_bv_previous_task = get_sub_dag_operator(sub_dag_func_owner_landing_views_bv_users,
                                                                      None,
                                                                      'amplitude_owner_landing_views_bv_previous',
                                                                      'top_funnel')
owner_landing_views_bv_sub_dag = get_sub_dag_operator(sub_dag_func_no_filters, materialize_growth_measure_table_query,
                                                      'owner_landing_views_bv', 'top_funnel')

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
prediction_visits_booked_sub_dag = get_sub_dag_operator(
    sub_dag_func=sub_dag_func_with_filters,
    materialize_func=materialize_growth_measure_prediction_table_query,
    sub_dag_name='prediction_visits_booked',
    funnel='demand',
    placeholders=get_visits_booked_placeholders())

prediction_visits_completed_sub_dag = get_sub_dag_operator(
    sub_dag_func=sub_dag_func_with_filters,
    materialize_func=materialize_growth_measure_prediction_table_query,
    sub_dag_name='prediction_visits_completed',
    funnel='demand',
    placeholders=get_visits_completed_placeholders())

prediction_offers_submitted_sub_dag = get_sub_dag_operator(
    sub_dag_func=sub_dag_func_with_filters,
    materialize_func=materialize_growth_measure_prediction_table_query,
    sub_dag_name='prediction_offers_submitted',
    funnel='demand',
    placeholders=get_offers_submitted_placeholders())

prediction_offers_approved_sub_dag = get_sub_dag_operator(
    sub_dag_func=sub_dag_func_with_filters,
    materialize_func=materialize_growth_measure_prediction_table_query,
    sub_dag_name='prediction_offers_approved',
    funnel='demand',
    placeholders=get_offers_approved_placeholders())

prediction_documentation_sent_sub_dag = get_sub_dag_operator(
    sub_dag_func=sub_dag_func_with_filters,
    materialize_func=materialize_growth_measure_prediction_table_query,
    sub_dag_name='prediction_documentation_sent',
    funnel='demand',
    placeholders=get_documentation_sent_placeholders())

prediction_approved_by_insurer_sub_dag = get_sub_dag_operator(
    sub_dag_func=sub_dag_func_with_filters,
    materialize_func=materialize_growth_measure_prediction_table_query,
    sub_dag_name='prediction_approved_by_insurer',
    funnel='demand',
    placeholders=get_approved_by_insurer_placeholders())

prediction_tenants_sub_dag = get_sub_dag_operator(sub_dag_func=sub_dag_func_with_filters,
                                                  materialize_func=materialize_growth_measure_prediction_table_query,
                                                  sub_dag_name='prediction_tenants',
                                                  funnel='demand',
                                                  placeholders=get_tenants_placeholders()
                                                  )

# fact append
fact_append_task = get_python_operator('append_predictions_fact_growth', append_predictions_fact_growth, main_dag)

# flow
amplitude_engaged_users_previous_task >> engaged_users_sub_dag
amplitude_schedule_page_views_previous_task >> schedule_page_views_sub_dag
amplitude_active_users_previous_task >> active_users_sub_dag
amplitude_owner_landing_views_previous_task >> owner_landing_views_sub_dag
amplitude_owner_landing_views_bv_previous_task >> owner_landing_views_bv_sub_dag
amplitude_listings_unique_page_views_previous_task >> listings_unique_page_views_sub_dag

(leads_sub_dag >> new_listings_sub_dag >> new_listings_landing_sub_dag >> new_listings_landing_bv_sub_dag >>
 opportunities_sub_dag >> prospects_sub_dag >> qualifieds_sub_dag >> ongoing_contracts_sub_dag >>
 engaged_users_sub_dag >> schedule_page_views_sub_dag >> active_users_sub_dag >> owner_landing_views_sub_dag >>
 owner_landing_views_bv_sub_dag >> listings_unique_page_views_sub_dag >> employees_sub_dag >>
 ticket_resolution_sub_dag >> tickets_sub_dag >> approved_by_insurer_sub_dag >> documentation_sent_sub_dag >>
 offerers_sub_dag >> offerers_approved_sub_dag >> offerers_sent_doc_sub_dag >> offers_approved_sub_dag >>
 offers_submitted_sub_dag >> tenant_prospects_sub_dag >> tenants_sub_dag >> ended_rentals_sub_dag >>
 visitors_sub_dag >> visits_booked_sub_dag >> visits_completed_sub_dag >> ongoing_listings_sub_dag >>
 ongoing_stranded_listings_sub_dag >> fact_task >> prediction_visits_booked_sub_dag >>
 prediction_visits_completed_sub_dag >> prediction_offers_submitted_sub_dag >> prediction_offers_approved_sub_dag >>
 prediction_documentation_sent_sub_dag >> prediction_approved_by_insurer_sub_dag >> prediction_tenants_sub_dag >>
 fact_append_task
 )
