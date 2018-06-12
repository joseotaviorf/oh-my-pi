from datetime import datetime

import bietlejuice.jobs.base.new_base_etl as utils
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.supply_demand_funnel.booking_subdag import BookingSubDag
from bietlejuice.jobs.dags.supply_demand_funnel.contract_subdag import ContractSubDag
from bietlejuice.jobs.dags.supply_demand_funnel.house_subdag import HouseSubDag
from bietlejuice.jobs.dags.supply_demand_funnel.lead_subdag import LeadSubDag
from bietlejuice.jobs.dags.supply_demand_funnel.offer_subdag import OfferSubDag
from bietlejuice.jobs.dags.supply_demand_funnel.photo_job_subdag import PhotoJobSubDag
from bietlejuice.jobs.dags.supply_demand_funnel.proposal_subdag import ProposalSubDag
from bietlejuice.jobs.dags.supply_demand_funnel.region_subdag import RegionSubDag
from bietlejuice.jobs.dags.supply_demand_funnel.user_subdag import UserSubDag
from bietlejuice.jobs.dags.supply_demand_funnel.visit_subdag import VisitSubDag
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.dags.util import xcom as xcom

env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS', 'EBDB', 'GODFATHER')
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')

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
    utils.extract_query_dim_from_ebdb_to_ods(
        dim_name=kwargs['dim_name'],
        bucket=bucket,
        command=kwargs['command'],
        table_name=None if 'table_name' not in kwargs else kwargs['table_name']
    )


def load_dim_from_ods_to_dw(**kwargs):
    utils.load_dim_from_ods_to_dw(
        dim_name=kwargs['dim_name'],
        bucket=bucket,
        is_fact=False if 'is_fact' not in kwargs else kwargs['is_fact'],
        pre_command=None if 'pre_command' not in kwargs else kwargs['pre_command'],
        post_command=None if 'post_command' not in kwargs else kwargs['post_command']
    )


def lead_sub_dag(sub_dag_name):
    sub_dag = LeadSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )
    return sub_dag.build_lead_with_tests()


def photo_job_sub_dag(sub_dag_name):
    sub_dag = PhotoJobSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )
    return sub_dag.build_photo_job_with_tests()


def region_sub_dag(sub_dag_name):
    sub_dag = RegionSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )
    return sub_dag.build_region_with_tests()


def user_sub_dag(sub_dag_name):
    sub_dag = UserSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )

    return sub_dag.build_user_with_tests()


def house_sub_dag(sub_dag_name):
    sub_dag = HouseSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )

    return sub_dag.build_house_with_tests()


def visit_sub_dag(sub_dag_name):
    sub_dag = VisitSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )

    return sub_dag.build_visit_with_tests()


def offer_sub_dag(sub_dag_name):
    sub_dag = OfferSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )

    return sub_dag.build_offer_with_tests()


def proposal_sub_dag(sub_dag_name):
    sub_dag = ProposalSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )

    return sub_dag.build_proposal_with_tests()


def contract_sub_dag(sub_dag_name):
    sub_dag = ContractSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )

    return sub_dag.build_contract_with_tests()


def booking_sub_dag(sub_dag_name):
    sub_dag = BookingSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )

    return sub_dag.build_booking_with_tests()


def xcom_fact_demand_task(**kwargs):
    exec_date = str(datetime.date(kwargs['execution_date']))
    xcom.xcom_push(kwargs['ti'], exec_date)


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
    op_kwargs={'dim_name': 'fact_supply',
               'command': 'call ebdb.list_fact_supply(null);'}
)

fact_supply = BaseDAG.get_quintoandar_python_operator(
    dag=main_dag,
    task_id='DW_Fact_Supply',
    func_command=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'supply', 'is_fact': True, 'bucket': bucket}
)

fact_photo_job = BaseDAG.get_quintoandar_python_operator(
    dag=main_dag,
    task_id='DW_fact_photo_job',
    func_command=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'photo_job', 'is_fact': True, 'bucket': bucket}
)

fact_demand = BaseDAG.get_quintoandar_python_operator(
    dag=main_dag,
    task_id='DW_fact_demand',
    func_command=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'demand', 'is_fact': True, 'bucket': bucket}
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

house_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=house_sub_dag,
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

xcom_fact_demand = BaseDAG.get_quintoandar_python_operator(
    dag=main_dag,
    task_id='XCom_fact_demand',
    func_command=xcom_fact_demand_task,
    provide_context=True
)

ods_supply.set_upstream([lead_dag, photo_job_dag, region_dag, user_dag, house_dag])
ods_house_rent_flow.set_upstream([booking_dag, visit_dag, offer_dag, proposal_dag, contract_dag, region_dag,
                                  user_dag, house_dag])

ods_supply >> fact_supply
ods_house_rent_flow >> fact_demand
fact_demand >> xcom_fact_demand
house_dag >> fact_photo_job
photo_job_dag >> fact_photo_job
