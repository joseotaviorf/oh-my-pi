from datetime import datetime

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.supply_demand_funnel import offer_subdag
from bietlejuice.jobs.dags.supply_demand_funnel.contract_subdag import ContractSubDag
from bietlejuice.jobs.dags.supply_demand_funnel.lead_subdag import LeadSubDag
from bietlejuice.jobs.dags.supply_demand_funnel.photo_job_subdag import PhotoJobSubDag
from bietlejuice.jobs.dags.supply_demand_funnel.region_subdag import RegionSubDag
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl.business_dim_etl import BusinessDimensionETL

env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS', 'EBDB', 'GODFATHER')
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
biz_etl = BusinessDimensionETL(bucket)

MAIN_DAG_NAME = 'bi-supply-demand-etl'
MAIN_START_DATE = datetime(2018, 4, 29, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = '0 2 * * *'

# create main DAG definition
main_dag = BaseDAG.build_dag(
    dag_id=MAIN_DAG_NAME,
    description='ETL pipeline for the entire BI funnel',
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL
)


def extract_query_dim_from_ebdb_to_ods(**kwargs):
    biz_etl.extract_query_dim_from_ebdb_to_ods(
        dim_name=kwargs['dim_name'],
        command=kwargs['command'],
        table_name=None if 'table_name' not in kwargs else kwargs['table_name']
    )


def extract_table_dim_from_ebdb_to_ods(**kwargs):
    biz_etl.extract_table_dim_from_ebdb_to_ods(
        dim_name=kwargs['dim_name'],
        table_name=kwargs['table_name'],
        add_timestamp=False if 'add_timestamp' not in kwargs else kwargs['add_timestamp'],
        copy_to_clean=True if 'copy_to_clean' not in kwargs else kwargs['copy_to_clean']
    )


def load_athena_file_query_to_ods(**kwargs):
    biz_etl.load_athena_file_query_to_ods(
        table_name=kwargs['table_name'],
        file_name=kwargs['file_name'],
        append=False if 'append' not in kwargs else kwargs['append']
    )


def load_athena_raw_query_to_ods(**kwargs):
    biz_etl.load_athena_raw_query_to_ods(
        table_name=kwargs['table_name'],
        query=kwargs['query'],
        append=False if 'append' not in kwargs else kwargs['append']
    )


def load_dim_from_ods_to_dw(**kwargs):
    biz_etl.load_dim_from_ods_to_dw(
        dim_name=kwargs['dim_name'],
        insert_dummy=True if 'insert_dummy' not in kwargs else kwargs['insert_dummy'],
        is_fact=False if 'is_fact' not in kwargs else kwargs['is_fact'],
        pre_command=None if 'pre_command' not in kwargs else kwargs['pre_command'],
        post_command=None if 'post_command' not in kwargs else kwargs['post_command']
    )


def materialize_view_ods(**kwargs):
    biz_etl.materialize_view_ods(
        view_name=kwargs['view_name'],
        append=False if 'append' not in kwargs else kwargs['append']
    )


def mock_run_dimension_tests():
    pass


def lead_sub_dag(sub_dag_name):
    sub_dag = LeadSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )
    return sub_dag.build()


def photo_job_sub_dag(sub_dag_name):
    sub_dag = PhotoJobSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )
    return sub_dag.build()


def region_sub_dag(sub_dag_name):
    sub_dag = RegionSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )
    return sub_dag.build()


def user_sub_dag(sub_dag_name):
    local_dag = BaseDAG.build_dag(
        '{}.{}'.format(MAIN_DAG_NAME, sub_dag_name),
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    user = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='ODS_user',
        func_command=extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'user', 'table_name': 'usuario', 'bucket': bucket,
                   'command': 'call ebdb.list_usuario();'}
    )

    dim_user_task = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='DW_dim_user',
        func_command=load_dim_from_ods_to_dw,
        op_kwargs={'dim_name': 'user', 'bucket': bucket}
    )

    test_user = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='TEST_dim_user',
        func_command=mock_run_dimension_tests
    )

    user >> dim_user_task >> test_user

    return local_dag


def property_sub_dag(sub_dag_name):
    local_dag = BaseDAG.build_dag(
        '{}.{}'.format(MAIN_DAG_NAME, sub_dag_name),
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    property_task = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='ODS_imovel',
        func_command=extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'property', 'bucket': bucket, 'command': 'call ebdb.list_imovel();',
                   'table_name': 'imovel'}
    )

    affiliate = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='ODS_affiliate_payments',
        func_command=load_athena_file_query_to_ods,
        op_kwargs={'table_name': 'affiliate_payments', 'file_name': 'affiliate_payments.sql'}
    )

    rent_flow = BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_rent_flow',
        dag=local_dag,
        func_command=extract_table_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'rental_flow', 'table_name': 'FluxoLocacao', 'copy_to_clean': False}
    )

    listing_views = BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_listing_views',
        dag=local_dag,
        func_command=load_athena_file_query_to_ods,
        op_kwargs={'table_name': 'listing_views', 'file_name': 'listing_views.sql'}
    )

    property_listing = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='ODS_property_listing',
        func_command=materialize_view_ods,
        op_kwargs={'view_name': 'property_listing'}
    )

    dim_property = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='DW_dim_property',
        func_command=load_dim_from_ods_to_dw,
        op_kwargs={'dim_name': 'property', 'bucket': bucket}
    )

    dim_status_over_period = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='DW_dim_property_status_over',
        func_command=load_dim_from_ods_to_dw,
        op_kwargs={'dim_name': 'property_status_over_period', 'bucket': bucket, 'insert_dummy': False}
    )

    test_property = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='TEST_dim_property',
        func_command=mock_run_dimension_tests
    )

    listing_views
    rent_flow >> dim_property
    affiliate >> property_task
    property_task >> dim_property
    property_listing >> dim_property
    dim_property >> dim_status_over_period
    dim_status_over_period >> test_property

    return local_dag


def visit_sub_dag(sub_dag_name):
    local_dag = BaseDAG.build_dag(
        '{}.{}'.format(MAIN_DAG_NAME, sub_dag_name),
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    visits = BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_visits',
        dag=local_dag,
        func_command=extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'visit', 'command': 'call ebdb.list_visita();'}
    )

    property_visit_information = BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_property_visit_information',
        dag=local_dag,
        func_command=load_athena_file_query_to_ods,
        op_kwargs={'table_name': 'property_visit_information', 'append': True,
                   'file_name': 'property_visit_information.sql'}
    )

    dim_visits = BaseDAG.get_quintoandar_python_operator(
        task_id='DW_dim_visits',
        dag=local_dag,
        func_command=load_dim_from_ods_to_dw,
        op_kwargs={'dim_name': 'visit'}
    )

    test_visits = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='TEST_dim_visits',
        func_command=mock_run_dimension_tests
    )

    property_visit_information >> visits
    visits >> dim_visits
    dim_visits >> test_visits

    return local_dag


def offer_sub_dag(sub_dag_name):
    return offer_subdag.build(
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )


def proposal_sub_dag(sub_dag_name):
    local_dag = BaseDAG.build_dag(
        '{}.{}'.format(MAIN_DAG_NAME, sub_dag_name),
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    proposal = BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_proposal',
        dag=local_dag,
        func_command=extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'proposal', 'command': 'call ebdb.list_proposta();'}
    )
    dim_negotiation = BaseDAG.get_quintoandar_python_operator(
        task_id='DW_dim_negotiation',
        dag=local_dag,
        func_command=load_dim_from_ods_to_dw,
        op_kwargs={'dim_name': 'negotiation'}
    )

    dim_proposal = BaseDAG.get_quintoandar_python_operator(
        task_id='DW_dim_proposal',
        dag=local_dag,
        func_command=load_dim_from_ods_to_dw,
        op_kwargs={'dim_name': 'proposal'}
    )

    test_proposal = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='TEST_dim_proposal',
        func_command=mock_run_dimension_tests
    )

    proposal >> dim_proposal
    dim_proposal >> test_proposal
    dim_negotiation

    return local_dag


def contract_sub_dag(sub_dag_name):
    sub_dag = ContractSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )

    return sub_dag.build_with_tests()


def booking_sub_dag(sub_dag_name):
    local_dag = BaseDAG.build_dag(
        '{}.{}'.format(MAIN_DAG_NAME, sub_dag_name),
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    booking = BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_booking',
        dag=local_dag,
        func_command=extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'booking', 'command': 'call ebdb.list_agendamento();'}
    )

    booking_media_sources_task = BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_booking_media_sources',
        dag=local_dag,
        func_command=load_athena_file_query_to_ods,
        op_kwargs={'table_name': 'booking_media_sources', 'file_name': 'extract_booking_media_sources.sql'}
    )

    dim_booking_task = BaseDAG.get_quintoandar_python_operator(
        task_id='DW_dim_booking',
        dag=local_dag,
        func_command=load_dim_from_ods_to_dw,
        op_kwargs={'dim_name': 'booking',
                   'post_command': "update dim_booking set visit_follow_up = null where visit_follow_up = ''"}
    )

    test_booking = BaseDAG.get_quintoandar_python_operator(
        dag=local_dag,
        task_id='TEST_dim_booking',
        func_command=mock_run_dimension_tests
    )

    booking >> dim_booking_task
    booking_media_sources_task >> dim_booking_task
    dim_booking_task >> test_booking

    return local_dag


ods_house_rent_flow = BaseDAG.get_quintoandar_python_operator(
    task_id='ODS_house_rent_flow',
    dag=main_dag,
    func_command=extract_query_dim_from_ebdb_to_ods,
    op_kwargs={'dim_name': 'house_rent_flow', 'command': 'call ebdb.list_house_rent_flow();'}
)

ods_supply = BaseDAG.get_quintoandar_python_operator(
    dag=main_dag,
    task_id='ODS_supply',
    func_command=extract_query_dim_from_ebdb_to_ods,
    op_kwargs={'dim_name': 'fact_supply', 'bucket': bucket,
               'command': 'call ebdb.list_fact_supply(null);'}
)

fact_supply = BaseDAG.get_quintoandar_python_operator(
    dag=main_dag,
    task_id='DW_Fact_Supply',
    func_command=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'supply', 'is_fact': True, 'bucket': bucket, 'insert_dummy': False}
)

fact_demand = BaseDAG.get_quintoandar_python_operator(
    dag=main_dag,
    task_id='DW_fact_demand',
    func_command=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'demand', 'is_fact': True, 'bucket': bucket, 'insert_dummy': False}
)

# flow
lead_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=lead_sub_dag,
    sub_dag_name='Lead'
)

photo_job_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=photo_job_sub_dag,
    sub_dag_name='PhotoJob'
)

region_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=region_sub_dag,
    sub_dag_name='Region'
)

user_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=user_sub_dag,
    sub_dag_name='User'
)

property_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=property_sub_dag,
    sub_dag_name='Property'
)

visit_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=visit_sub_dag,
    sub_dag_name='Visit'
)

offer_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=offer_sub_dag,
    sub_dag_name='Offer'
)

proposal_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=proposal_sub_dag,
    sub_dag_name='Proposal'
)

contract_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=contract_sub_dag,
    sub_dag_name='Contract'
)

booking_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=booking_sub_dag,
    sub_dag_name='Booking'
)

ods_supply.set_upstream([lead_dag, photo_job_dag, region_dag, user_dag, property_dag])
ods_house_rent_flow.set_upstream([booking_dag, visit_dag, offer_dag, proposal_dag, contract_dag, region_dag,
                                  user_dag, property_dag])

ods_supply >> fact_supply
ods_house_rent_flow >> fact_demand
