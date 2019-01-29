from datetime import datetime

import airflow.utils.helpers as airflow_helpers
import bietlejuice.jobs.base.new_base_etl as utils
import bietlejuice.jobs.etl.powerbi as powerbi
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags import SOURCE_QUERIES_DIR
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

PWBI_AUTH = env.get_airflow_env_var('PWBI_AUTH')
PWBI_SCHEMA = env.get_airflow_env_var('PWBI_SCHEMA')

MAIN_DAG_NAME = 'bi-supply-demand-etl'
MAIN_START_DATE = datetime(2018, 4, 29, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = '0 5 * * *'

# create main DAG definition
main_dag = BaseDAG.build_dag(
    dag_id=MAIN_DAG_NAME,
    description='ETL pipeline for the entire BI funnel',
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL
)


def extract_query_dim_from_ebdb_to_ods(**kwargs):
    file_path = '{}/ebdb/supply_demand_funnel/{}.sql'.format(SOURCE_QUERIES_DIR, kwargs['table_name'])
    query = BaseETL.get_query_from_file_name(file_name=file_path)

    if 'execution_date' in kwargs:
        query = query.format(str(kwargs['execution_date']))

    utils.extract_query_dim_from_ebdb_to_ods(
        dim_name=kwargs['table_name'],
        bucket=bucket,
        command=query,
        table_name=None if 'table_name' not in kwargs else kwargs['table_name']
    )


def load_dim_from_ods_to_dw(**kwargs):
    utils.load_dim_from_ods_to_dw(
        dim_name=kwargs['dim_name'],
        bucket=bucket,
        insert_dummy=True if 'insert_dummy' not in kwargs else kwargs['insert_dummy'],
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


def refresh_powerbi(**kwargs):
    powerbi_client = powerbi.PowerBIClient(PWBI_AUTH,
                                           PWBI_SCHEMA,
                                           kwargs['workspace_name'],
                                           kwargs['dataset_name'])
    powerbi_client.trigger_refresh()


def xcom_fact_listing_rent_flows_task(**kwargs):
    exec_date = str(datetime.date(kwargs['execution_date']))
    xcom.xcom_push(kwargs['ti'], exec_date)


ods_house_rent_flow = BaseDAG.build_pyton_operator(
    task_id='ODS_house_rent_flow',
    dag=main_dag,
    python_callable=extract_query_dim_from_ebdb_to_ods,
    op_kwargs={'table_name': 'house_rent_flow'}
)

ods_supply = BaseDAG.build_pyton_operator(
    dag=main_dag,
    task_id='ODS_supply',
    provide_context=True,
    python_callable=extract_query_dim_from_ebdb_to_ods,
    op_kwargs={'table_name': 'fact_supply'}
)

fact_supply = BaseDAG.build_pyton_operator(
    dag=main_dag,
    task_id='DW_Fact_Supply',
    python_callable=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'supply', 'is_fact': True, 'bucket': bucket, 'insert_dummy': False}
)

fact_house_listings = BaseDAG.build_pyton_operator(
    dag=main_dag,
    task_id='DW_Fact_House_Listings',
    python_callable=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'house_listings', 'is_fact': True, 'bucket': bucket, 'insert_dummy': False}
)

fact_photo_job = BaseDAG.build_pyton_operator(
    dag=main_dag,
    task_id='DW_fact_photo_job',
    python_callable=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'photo_job', 'is_fact': True, 'bucket': bucket, 'insert_dummy': False}
)

fact_listing_rent_flows = BaseDAG.build_pyton_operator(
    dag=main_dag,
    task_id='DW_fact_listing_rent_flows',
    python_callable=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'listing_rent_flows', 'is_fact': True, 'bucket': bucket}
)

fact_house_status = BaseDAG.build_pyton_operator(
    dag=main_dag,
    task_id='DW_fact_house_status',
    python_callable=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'house_status', 'is_fact': True, 'bucket': bucket}
)

# new 'supply' flow
ods_house_listing_flows = BaseDAG.build_pyton_operator(
    dag=main_dag,
    task_id='ODS_House_Listing_Flows',
    provide_context=True,
    python_callable=extract_query_dim_from_ebdb_to_ods,
    op_kwargs={'table_name': 'fact_house_listing_flows'}
)

dw_fact_house_listing_flows = BaseDAG.build_pyton_operator(
    dag=main_dag,
    task_id='DW_Fact_House_Listing_Flows',
    python_callable=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'house_listing_flows', 'is_fact': True, 'bucket': bucket, 'insert_dummy': False}
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
    sub_dag_name='House'
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

xcom_fact_listing_rent_flows = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='XCom_fact_listing_rent_flows',
    python_callable=xcom_fact_listing_rent_flows_task,
    provide_context=True
)

refresh_supply = BaseDAG.build_pyton_operator(
    dag=main_dag,
    task_id='Refresh_PowerBI_Supply',
    python_callable=refresh_powerbi,
    op_kwargs={'workspace_name': 'QuintoAndar', 'dataset_name': 'Supply'}
)

refresh_house_listing_flows = BaseDAG.build_pyton_operator(
    dag=main_dag,
    task_id='Refresh_PowerBI_House_Listing_Flows',
    python_callable=refresh_powerbi,
    op_kwargs={'workspace_name': 'Data', 'dataset_name': 'House Listing Flow'}
)

refresh_listing_rent_flows = BaseDAG.build_pyton_operator(
    dag=main_dag,
    task_id='Refresh_PowerBI_Listing_Rent_Flows',
    python_callable=refresh_powerbi,
    op_kwargs={'workspace_name': 'QuintoAndar', 'dataset_name': 'Rent Flow'}
)

refresh_booking = BaseDAG.build_pyton_operator(
    dag=main_dag,
    task_id='Refresh_PowerBI_Booking',
    python_callable=refresh_powerbi,
    op_kwargs={'workspace_name': 'Conversion', 'dataset_name': 'Booking'}
)

ods_supply.set_upstream([lead_dag, photo_job_dag, region_dag, user_dag, house_dag])
fact_listing_rent_flows.set_upstream([booking_dag, visit_dag, offer_dag, proposal_dag, contract_dag, region_dag,
                                      user_dag, house_dag, ods_house_rent_flow])
airflow_helpers.chain(ods_supply, fact_supply, refresh_supply)
fact_listing_rent_flows.set_downstream([xcom_fact_listing_rent_flows, refresh_listing_rent_flows])
refresh_listing_rent_flows >> refresh_booking
house_dag >> fact_photo_job
photo_job_dag >> fact_photo_job
house_dag.set_downstream([fact_house_status, fact_house_listings])
# new 'supply' flow
ods_house_listing_flows.set_upstream([lead_dag, photo_job_dag, region_dag, user_dag, house_dag])
airflow_helpers.chain(ods_house_listing_flows, dw_fact_house_listing_flows, refresh_house_listing_flows)
