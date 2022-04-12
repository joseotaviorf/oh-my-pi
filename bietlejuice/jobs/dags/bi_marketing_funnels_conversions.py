from datetime import datetime

import airflow.utils.helpers as airflow_helpers
from airflow.executors import LocalExecutor
from airflow.models import DAG
from airflow.operators.subdag_operator import SubDagOperator
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDB
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.marketing_funnels_conversions import FunnelConversionSubDag
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl import DW_QUERIES_DIR
from bietlejuice.jobs.etl.amplitude.growth_amplitude import GrowthAmplitude
from bietlejuice.jobs.etl.growth.incurred import Growth
from qa_python_utils import QuintoAndarLogger

env.set_airflow_var_to_local_env('BI_DW', 'DATA_AWS_ACCESS_KEY_ID', 'DATA_AWS_SECRET_ACCESS_KEY')
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')

MAIN_DAG_NAME = 'bi-marketing-funnels-conversions'
MAIN_START_DATE = datetime(2019, 1, 5)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule("0 7,13 * * *")

logger = QuintoAndarLogger(MAIN_DAG_NAME)

# create DAG definition
main_dag = DAG(
    dag_id=MAIN_DAG_NAME,
    description='ETL Pipeline for creating Conversion Points and cost Model in DW',
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,  # depends on datalake_marketing_costs_prod.daily_costs, which finishes at ~5h30 and ~12h00
    max_active_runs=1,
    catchup=False,
    orientation='TB'
)


@logger
def materialize_growth_measure_table_query(**kwargs):
    funnel = kwargs['funnel']
    measure = kwargs['measure']
    _filter = kwargs['filter']
    period = kwargs['period']
    is_taxonomy = (funnel == 'taxonomy')

    Growth.drop_table(table_name='{}_{}_{}_{}'.format(funnel, measure, _filter, period), schema=Growth.SCHEMA)
    Growth.create_table(funnel, measure, _filter, period, is_taxonomy=is_taxonomy, is_from_dw=True)


@logger
def materialize_growth_measure_table_from_datalake(**kwargs):
    funnel = kwargs['funnel']
    measure = kwargs['measure']
    _filter = kwargs['filter']
    period = kwargs['period']
    is_taxonomy = (funnel == 'taxonomy')

    Growth.drop_table(table_name='{}_{}_{}_{}'.format(funnel, measure, _filter, period), schema=Growth.SCHEMA)
    Growth.create_table(funnel, measure, _filter, period, is_taxonomy=is_taxonomy, is_from_dw=False)


@logger
def consolidate_with_filters(measure, is_taxonomy=False):
    Growth.drop_table(table_name=measure, schema=Growth.SCHEMA)

    consolidation_query = Growth.get_measure_all_query(is_taxonomy)
    Growth.execute_command(consolidation_query.format(measure))


def get_sub_dag_operator(sub_dag_func, materialize_func, sub_dag_name, funnel=None, placeholders=None,
                         truncate_func=None):
    return SubDagOperator(
        subdag=sub_dag_func(MAIN_DAG_NAME, sub_dag_name, funnel, main_dag.start_date, main_dag.schedule_interval,
                            materialize_func, placeholders, truncate_func),
        task_id=sub_dag_name if funnel != 'taxonomy' else '{}_{}'.format(funnel, sub_dag_name),
        dag=main_dag,
        executor=LocalExecutor(),
        execution_timeout=BaseDAG.EXECUTION_TIMEOUT,
        retries=BaseDAG.OPERATOR_RETRIES['retries'],
        retry_delay=BaseDAG.OPERATOR_RETRIES['retry_delay'],
        max_retry_delay=BaseDAG.OPERATOR_RETRIES['max_retry_delay']
    )


def get_filter_tasks(_filter, funnel, local_dag, sub_dag_name, materialize_func, placeholders):
    filter_day_task = BaseDAG.build_python_operator(task_id='extract_{}_{}_day'.format(sub_dag_name, _filter),
                                                    python_callable=materialize_func,
                                                    dag=local_dag,
                                                    op_kwargs={'funnel': funnel, 'measure': sub_dag_name,
                                                               'filter': _filter,
                                                               'period': 'day', 'placeholders': placeholders}
                                                    )

    filter_week_task = BaseDAG.build_python_operator(task_id='extract_{}_{}_week'.format(sub_dag_name, _filter),
                                                     python_callable=materialize_func,
                                                     dag=local_dag,
                                                     op_kwargs={'funnel': funnel, 'measure': sub_dag_name,
                                                                'filter': _filter,
                                                                'period': 'week', 'placeholders': placeholders}
                                                     )

    filter_month_task = BaseDAG.build_python_operator(task_id='extract_{}_{}_month'.format(sub_dag_name, _filter),
                                                      python_callable=materialize_func,
                                                      dag=local_dag,
                                                      op_kwargs={'funnel': funnel, 'measure': sub_dag_name,
                                                                 'filter': _filter,
                                                                 'period': 'month', 'placeholders': placeholders}
                                                      )

    filter_year_task = BaseDAG.build_python_operator(task_id='extract_{}_{}_year'.format(sub_dag_name, _filter),
                                                     python_callable=materialize_func,
                                                     dag=local_dag,
                                                     op_kwargs={'funnel': funnel, 'measure': sub_dag_name,
                                                                'filter': _filter,
                                                                'period': 'year', 'placeholders': placeholders}
                                                     )

    return filter_day_task, filter_week_task, filter_month_task, filter_year_task


def sub_dag_func_taxonomy(main_dag_name, sub_dag_name, funnel, start_date, schedule_interval, materialize_func,
                          placeholders, truncate_func):
    full_sub_dag_name = '{}_{}'.format(funnel, sub_dag_name)

    local_dag = DAG(
        '{}.{}'.format(main_dag_name, full_sub_dag_name),
        schedule_interval=schedule_interval,
        start_date=start_date
    )

    # city
    city_tasks = get_filter_tasks('city', funnel, local_dag, sub_dag_name, materialize_func, placeholders)

    consolidation_task = BaseDAG.build_python_operator(task_id='consolidate',
                                                       python_callable=consolidate_with_filters,
                                                       dag=local_dag,
                                                       op_kwargs={
                                                           'measure': full_sub_dag_name,
                                                           'is_taxonomy': True}
                                                       )
    consolidation_task.set_upstream(city_tasks)

    return local_dag


def move_file_query_data_to_dw(schema, file_name):
    query = BaseETL.get_query_from_file_name(file_name='{}/{}/{}.sql'.format(DW_QUERIES_DIR, schema, file_name))

    table = BaseETL.from_db_query(
        db_enum=EnumDB.BI_DW,
        query=query)

    BaseETL.bulk_insert(
        table=table,
        table_name='{}.{}'.format(schema, file_name),
        db_enum=EnumDB.BI_DW,
        encoding='UTF-8',
        append=False
    )


def create_supply_funnel_conversions_sub_dag(sub_dag_name):
    sub_dag = FunnelConversionSubDag(
        bucket=bucket,
        schedule_interval=None,
        start_date=MAIN_START_DATE,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        funnel_side='supply'
    )

    return sub_dag.build_subdag()


def create_demand_funnel_conversions_sub_dag(sub_dag_name):
    sub_dag = FunnelConversionSubDag(
        bucket=bucket,
        schedule_interval=None,
        start_date=MAIN_START_DATE,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        funnel_side='demand'
    )

    return sub_dag.build_subdag()


# measures with taxonomy detail
taxonomy_leads_sub_dag = get_sub_dag_operator(sub_dag_func_taxonomy,
                                              materialize_growth_measure_table_query,
                                              'leads',
                                              'taxonomy')

taxonomy_prospects_sub_dag = get_sub_dag_operator(sub_dag_func_taxonomy,
                                                  materialize_growth_measure_table_query,
                                                  'prospects',
                                                  'taxonomy')

taxonomy_qualifieds_sub_dag = get_sub_dag_operator(sub_dag_func_taxonomy,
                                                   materialize_growth_measure_table_query,
                                                   'qualifieds',
                                                   'taxonomy')

taxonomy_opportunities_sub_dag = get_sub_dag_operator(sub_dag_func_taxonomy,
                                                      materialize_growth_measure_table_query,
                                                      'opportunities',
                                                      'taxonomy')

taxonomy_visits_booked_sub_dag = get_sub_dag_operator(sub_dag_func_taxonomy,
                                                      materialize_growth_measure_table_query,
                                                      'visits_booked',
                                                      'taxonomy')

taxonomy_visits_completed_sub_dag = get_sub_dag_operator(sub_dag_func_taxonomy,
                                                         materialize_growth_measure_table_query,
                                                         'visits_completed',
                                                         'taxonomy')

taxonomy_offers_submitted_sub_dag = get_sub_dag_operator(sub_dag_func_taxonomy,
                                                         materialize_growth_measure_table_query,
                                                         'offers_submitted',
                                                         'taxonomy')

taxonomy_offers_approved_sub_dag = get_sub_dag_operator(sub_dag_func_taxonomy,
                                                        materialize_growth_measure_table_query,
                                                        'offers_approved',
                                                        'taxonomy')

taxonomy_contracts_signed_sub_dag = get_sub_dag_operator(sub_dag_func_taxonomy,
                                                         materialize_growth_measure_table_query,
                                                         'contracts_signed',
                                                         'taxonomy')

taxonomy_listings_sub_dag = get_sub_dag_operator(sub_dag_func_taxonomy,
                                                 materialize_growth_measure_table_query,
                                                 'listings',
                                                 'taxonomy')

create_conversion_points_supply_daily_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='create_conversion_points_supply_daily',
    python_callable=GrowthAmplitude.create_table_as_file_query,
    op_kwargs={'table_name': 'conversion_points_supply_daily', 'level': 'taxonomy',
               'sub_level': 'conversion_points_supply'}
)

create_conversion_points_demand_daily_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='create_conversion_points_demand_daily',
    python_callable=GrowthAmplitude.create_table_as_file_query,
    op_kwargs={'table_name': 'conversion_points_demand_daily', 'level': 'taxonomy',
               'sub_level': 'conversion_points_demand'}
)

create_conversion_points_supply_weekly_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='create_conversion_points_supply_weekly',
    python_callable=GrowthAmplitude.create_table_as_file_query,
    op_kwargs={'table_name': 'conversion_points_supply_weekly', 'level': 'taxonomy',
               'sub_level': 'conversion_points_supply'}
)

create_conversion_points_demand_weekly_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='create_conversion_points_demand_weekly',
    python_callable=GrowthAmplitude.create_table_as_file_query,
    op_kwargs={'table_name': 'conversion_points_demand_weekly', 'level': 'taxonomy',
               'sub_level': 'conversion_points_demand'}
)

create_conversion_points_supply_monthly_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='create_conversion_points_supply_monthly',
    python_callable=GrowthAmplitude.create_table_as_file_query,
    op_kwargs={'table_name': 'conversion_points_supply_monthly', 'level': 'taxonomy',
               'sub_level': 'conversion_points_supply'}
)

create_conversion_points_demand_monthly_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='create_conversion_points_demand_monthly',
    python_callable=GrowthAmplitude.create_table_as_file_query,
    op_kwargs={'table_name': 'conversion_points_demand_monthly', 'level': 'taxonomy',
               'sub_level': 'conversion_points_demand'}
)

supply_funnel_conversions_subdag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=create_supply_funnel_conversions_sub_dag,
    sub_dag_name='supply_funnel_conversions'
)

demand_funnel_conversions_subdag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=create_demand_funnel_conversions_sub_dag,
    sub_dag_name='demand_funnel_conversions'
)

# flow
create_conversion_points_supply_daily_task.set_upstream([taxonomy_leads_sub_dag,
                                                         taxonomy_prospects_sub_dag,
                                                         taxonomy_qualifieds_sub_dag,
                                                         taxonomy_opportunities_sub_dag,
                                                         taxonomy_listings_sub_dag])
create_conversion_points_demand_daily_task.set_upstream([taxonomy_visits_booked_sub_dag,
                                                         taxonomy_visits_completed_sub_dag,
                                                         taxonomy_offers_submitted_sub_dag,
                                                         taxonomy_offers_approved_sub_dag,
                                                         taxonomy_contracts_signed_sub_dag])
airflow_helpers.chain(create_conversion_points_supply_daily_task,
                      create_conversion_points_supply_weekly_task,
                      create_conversion_points_supply_monthly_task)
airflow_helpers.chain(create_conversion_points_demand_daily_task,
                      create_conversion_points_demand_weekly_task,
                      create_conversion_points_demand_monthly_task)
supply_funnel_conversions_subdag.set_upstream([create_conversion_points_supply_monthly_task,
                                               create_conversion_points_demand_monthly_task])
airflow_helpers.chain(supply_funnel_conversions_subdag,
                      demand_funnel_conversions_subdag)
