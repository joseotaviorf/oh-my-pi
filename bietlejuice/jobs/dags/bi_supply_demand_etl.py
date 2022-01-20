import os
from datetime import datetime, date, timedelta

import bietlejuice.jobs.base.new_base_etl as utils

from airflow.operators.dagrun_operator import TriggerDagRunOperator
from airflow.operators.sensors import S3KeySensor

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.dags import (
    SOURCE_QUERIES_DIR,
    DW_QUERIES_DIR,
    DATALAKE_QUERIES_DIR,
)
from bietlejuice.jobs.dags.supply_demand_funnel import (
    BookingSubDag,
    ContractSubDag,
    ReservationSubDag,
    BankSubDag,
    HouseSubDag,
    LeadSubDag,
    OfferSubDag,
    PhotoJobSubDag,
    ProposalSubDag,
    RegionSubDag,
    UserSubDag,
    VisitSubDag,
    BankAccountSubDag,
    BankTransactionSubDag,
    AffiliateSubDag,
    DoormanSubDag,
    CondoSubDag,
    PartnerSubDag,
    PartnerAgentSubDag,
    InspectionSubDag,
    LeadConversionSubDag,
    SpecialConditionSubDag,
    ListingFlowsSubDag,
    SalesListingFlowsSubDag,
)
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.dags.util import xcom as xcom
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

logger = QuintoAndarLogger("bi-supply-demand-etl")

env.set_airflow_var_to_local_env(
    "BI_DW",
    "BI_ODS",
    "EBDB",
    "GODFATHER",
    "DATA_ACC_AWS_ACCESS_KEY_ID",
    "DATA_ACC_AWS_SECRET_ACCESS_KEY",
)
bucket = env.get_airflow_env_var("bi-datalake-s3-bucket")

MAIN_DAG_NAME = "bi-supply-demand-etl"
MAIN_START_DATE = datetime(2018, 4, 29, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = "30 4 * * *"

# create main DAG definition
main_dag = BaseDAG.build_dag(
    dag_id=MAIN_DAG_NAME,
    description="ETL pipeline for the entire BI funnel",
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
)


def extract_query_dim_from_ebdb_to_ods(**kwargs):
    file_path = "{}/ebdb/supply_demand_funnel/{}.sql".format(
        SOURCE_QUERIES_DIR, kwargs["table_name"]
    )
    query = BaseETL.get_query_from_file_name(file_name=file_path)

    if "execution_date" in kwargs:
        query = query.format(str(kwargs["execution_date"]))

    utils.extract_query_dim_from_ebdb_to_ods(
        dim_name=kwargs["table_name"],
        bucket=bucket,
        command=query,
        table_name=None if "table_name" not in kwargs else kwargs["table_name"],
    )


def load_dim_from_ods_to_dw(**kwargs):
    if "post_command_file" in kwargs:
        file_path = "{}/public/post_command_{}.sql".format(
            DW_QUERIES_DIR, kwargs["dim_name"]
        )
        post_command = BaseETL.get_query_from_file_name(file_name=file_path)
    else:
        post_command = None if "post_command" not in kwargs else kwargs["post_command"]

    utils.load_dim_from_ods_to_dw(
        dim_name=kwargs["dim_name"],
        bucket=bucket,
        insert_dummy=True if "insert_dummy" not in kwargs else kwargs["insert_dummy"],
        is_fact=False if "is_fact" not in kwargs else kwargs["is_fact"],
        pre_command=None if "pre_command" not in kwargs else kwargs["pre_command"],
        post_command=post_command,
        schema_dest="public" if "schema_dest" not in kwargs else kwargs["schema_dest"],
        schema_source="public"
        if "schema_source" not in kwargs
        else kwargs["schema_source"],
    )


@logger(exclude="kwargs")
def xcom_dependencies(task_id, dag_id, **kwargs):
    exec_date = str(datetime.date(kwargs["execution_date"]))

    status = xcom.xcom_pull(
        task_instance=kwargs["ti"], key=exec_date, task_id=task_id, dag_id=dag_id
    )
    if not status:
        raise ValueError(
            "m=xcom_dependencies, exec_date={}, dag_id={}, task_id={}, msg=The process have not finished yet".format(
                exec_date, dag_id, task_id
            )
        )

    logger.info(
        "m=xcom_dependencies, exec_date={}, dag_id={}, task_id={}, msg=REQUIREMENT MET".format(
            exec_date, dag_id, task_id
        )
    )


@logger(exclude=["kwargs", "query_params"])
def create_table_in_db_from_datalake(table_name, query_params, **kwargs):
    # setting variables
    file_path = "{}/{}{}.sql".format(
        DATALAKE_QUERIES_DIR, kwargs.get("file_path", ""), table_name
    )
    data_acc_aws_access_key_id = os.environ.get("DATA_ACC_AWS_ACCESS_KEY_ID")
    data_acc_aws_secret_access_key = os.environ.get("DATA_ACC_AWS_SECRET_ACCESS_KEY")
    athena_client = AthenaClient(
        bucket, data_acc_aws_access_key_id, data_acc_aws_secret_access_key
    )

    # executing methods
    df = athena_client.execute_file_query_and_return_dataframe(
        filename=file_path, query_params=query_params
    )

    if len(df.index) == 0:
        raise ValueError(
            "m=create_table_in_db_from_datalake, filename={}, msg=Query returned empty df".format(
                file_path
            )
        )

    BaseETL.dataframe_to_db(
        df=df,
        table_name=table_name,
        enum_db=kwargs.get("enum_db", EnumDB.BI_DW),
        encoding="utf-8",
        append=False,
    )


def lead_sub_dag(sub_dag_name):
    sub_dag = LeadSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )
    return sub_dag.build_lead_with_tests()


def lead_conversion_sub_dag(sub_dag_name):
    sub_dag = LeadConversionSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )
    return sub_dag.build_lead_conversion()


def photo_job_sub_dag(sub_dag_name):
    sub_dag = PhotoJobSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )
    return sub_dag.build_photo_job_with_tests()


def region_sub_dag(sub_dag_name):
    sub_dag = RegionSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )
    return sub_dag.build_region_with_tests()


def user_sub_dag(sub_dag_name):
    sub_dag = UserSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    return sub_dag.build_user_with_tests()


def inspection_sub_dag(sub_dag_name):
    sub_dag = InspectionSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    return sub_dag.build_inspection_with_tests()


def house_sub_dag(sub_dag_name):
    sub_dag = HouseSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    return sub_dag.build_house_with_tests()


def reservation_sub_dag(sub_dag_name):
    sub_dag = ReservationSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )
    return sub_dag.build_tasks_with_tests()


def visit_sub_dag(sub_dag_name):
    sub_dag = VisitSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    return sub_dag.build_visit_with_tests()


def offer_sub_dag(sub_dag_name):
    sub_dag = OfferSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    return sub_dag.build_offer_with_tests()


def proposal_sub_dag(sub_dag_name):
    sub_dag = ProposalSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    return sub_dag.build_proposal_with_tests()


def contract_sub_dag(sub_dag_name):
    sub_dag = ContractSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    return sub_dag.build_contract_with_tests()


def partner_sub_dag(sub_dag_name):
    sub_dag = PartnerSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    return sub_dag.build_partner_with_tests()


def partner_agent_sub_dag(sub_dag_name):
    sub_dag = PartnerAgentSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    return sub_dag.build_partner_agent_with_tests()


def booking_sub_dag(sub_dag_name):
    sub_dag = BookingSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    return sub_dag.build_booking_with_tests()


def condo_sub_dag(sub_dag_name):
    sub_dag = CondoSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    return sub_dag.build_condo_with_tests()


def bank_sub_dag(sub_dag_name):
    sub_dag = BankSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    return sub_dag.build_bank_with_tests()


def bank_account_sub_dag(sub_dag_name):
    sub_dag = BankAccountSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    return sub_dag.build_bank_account_with_tests()


def bank_transaction_sub_dag(sub_dag_name):
    sub_dag = BankTransactionSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    return sub_dag.build_bank_transaction()


def affiliate_sub_dag(sub_dag_name):
    sub_dag = AffiliateSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    return sub_dag.build_affiliate_with_tests()


def doorman_sub_dag(sub_dag_name):
    sub_dag = DoormanSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    return sub_dag.build_doorman_with_tests()


def special_condition_sub_dag(sub_dag_name):
    sub_dag = SpecialConditionSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )
    return sub_dag.build_special_condition()


def listing_flows_sub_dag(sub_dag_name):
    sub_dag = ListingFlowsSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )
    return sub_dag.build_listing_flows()


def sales_listing_flows_sub_dag(sub_dag_name):
    sub_dag = SalesListingFlowsSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )
    return sub_dag.build_sales_listing_flows()


amplitude_partner_taxonomy = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id="ODS_amplitude_partner_taxonomy",
    python_callable=utils.load_athena_file_query_to_ods,
    op_kwargs={
        "table_name": "amplitude_partner_taxonomy",
        "file_name": "amplitude_partner_taxonomy.sql",
        "bucket": bucket,
    },
)


ods_house_rent_flow = BaseDAG.build_python_operator(
    task_id="ODS_house_rent_flow",
    dag=main_dag,
    python_callable=extract_query_dim_from_ebdb_to_ods,
    op_kwargs={"table_name": "house_rent_flow"},
)

fact_photo_job = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id="DW_fact_photo_job",
    python_callable=load_dim_from_ods_to_dw,
    op_kwargs={
        "dim_name": "photo_job",
        "is_fact": True,
        "bucket": bucket,
        "insert_dummy": False,
    },
)

ods_fact_house_listing_status_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id="ODS_fact_house_listing_status",
    python_callable=create_table_in_db_from_datalake,
    op_kwargs={
        "table_name": "house_listing_status",
        "file_path": "house/",
        "query_params": None,
        "enum_db": EnumDB.BI_ODS,
    },
)

fact_inspection_bookings_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id="DW_fact_inspection_bookings",
    python_callable=load_dim_from_ods_to_dw,
    op_kwargs={"dim_name": "inspection_bookings", "is_fact": True, "bucket": bucket},
)

# new 'supply' flow
ods_house_listing_flows = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id="ODS_House_Listing_Flows",
    provide_context=True,
    python_callable=extract_query_dim_from_ebdb_to_ods,
    execution_timeout=timedelta(hours=7),
    op_kwargs={"table_name": "fact_house_listing_flows"},
)

fact_lead_task_contact_flows_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id="Fact_Lead_Task_Contact_Flows",
    python_callable=create_table_in_db_from_datalake,
    op_kwargs={
        "query_params": {"task_types": "'ConverterLead', 'ConverterLeadPrioritario'"},
        "table_name": "fact_lead_task_contact_flows",
    },
)


ods_credit_evaluation_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id="ODS_credit_evaluation",
    python_callable=create_table_in_db_from_datalake,
    op_kwargs={
        "table_name": "credit_evaluation",
        "query_params": None,
        "enum_db": EnumDB.BI_ODS,
    },
)

# flow
lead_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag, sub_dag_func=lead_sub_dag, sub_dag_name="Lead"
)

lead_conversion_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag, sub_dag_func=lead_conversion_sub_dag, sub_dag_name="LeadConversion"
)

photo_job_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag, sub_dag_func=photo_job_sub_dag, sub_dag_name="PhotoJob"
)

region_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag, sub_dag_func=region_sub_dag, sub_dag_name="Region"
)

user_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag, sub_dag_func=user_sub_dag, sub_dag_name="User"
)

inspection_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag, sub_dag_func=inspection_sub_dag, sub_dag_name="Inspection"
)

house_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag, sub_dag_func=house_sub_dag, sub_dag_name="House"
)

reservation_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag, sub_dag_func=reservation_sub_dag, sub_dag_name="Reservation"
)

visit_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag, sub_dag_func=visit_sub_dag, sub_dag_name="Visit"
)

offer_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag, sub_dag_func=offer_sub_dag, sub_dag_name="Offer"
)

proposal_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag, sub_dag_func=proposal_sub_dag, sub_dag_name="Proposal"
)

contract_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag, sub_dag_func=contract_sub_dag, sub_dag_name="Contract"
)

partner_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag, sub_dag_func=partner_sub_dag, sub_dag_name="Partner"
)

partner_agent_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag, sub_dag_func=partner_agent_sub_dag, sub_dag_name="PartnerAgent"
)

booking_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag, sub_dag_func=booking_sub_dag, sub_dag_name="Booking"
)

bank_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag, sub_dag_func=bank_sub_dag, sub_dag_name="Bank"
)

bank_account_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag, sub_dag_func=bank_account_sub_dag, sub_dag_name="BankAccount"
)

bank_transaction_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag, sub_dag_func=bank_transaction_sub_dag, sub_dag_name="BankTransaction"
)

condo_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag, sub_dag_func=condo_sub_dag, sub_dag_name="Condo"
)

affiliate_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag, sub_dag_func=affiliate_sub_dag, sub_dag_name="Affiliate"
)

doorman_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag, sub_dag_func=doorman_sub_dag, sub_dag_name="Doorman"
)

special_condition_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=special_condition_sub_dag,
    sub_dag_name="SpecialCondition",
)

listing_flows_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag, sub_dag_func=listing_flows_sub_dag, sub_dag_name="ListingFlows"
)

dw_sale_fact_listing_flows_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=sales_listing_flows_sub_dag,
    sub_dag_name="SalesListingFlows",
)

# TODO Recreate amplitude xcom after the data flow is fully fixed
# check the dependency of amplitude_load_events
# xcom_amplitude_task = BaseDAG.build_python_operator(
#     dag=main_dag,
#     task_id='xcom_amplitude',
#     provide_context=True,
#     python_callable=xcom_dependencies,
#     op_kwargs={'task_id': 'XCom_amplitude_load_events',
#                'dag_id': 'bi-amplitude-load-events'},
#     retry_delay=timedelta(minutes=10),
#     max_retry_delay=timedelta(minutes=10),
#     retries=15
# )

# trigger bi-growth dag after all tasks have been successfully completed
trigger_bi_growth_dag_task = TriggerDagRunOperator(
    dag=main_dag,
    task_id="trigger_bi_growth_dag",
    trigger_dag_id="bi-growth",
    execution_date="{{ execution_date }}",
)


# TODO Remove these file sensors
last_dep_execution_date = str(date.today() - timedelta(days=1))

amplitude_dep = S3KeySensor(
    task_id="amplitude_dep",
    poke_interval=3*60,
    timeout=2*60*60,
    aws_conn_id="aws_prod_data",
    bucket_name='5a-datalake-prod',
    bucket_key="dags_execution_logs/{execution_date}/{dependency_dag}.SUCCESS".format(execution_date=last_dep_execution_date, dependency_dag='bietlejuice.amplitude'),
    dag=main_dag
)

enrich_amplitude_partner_taxonomy_dep = S3KeySensor(
    task_id="enrich_amplitude_partner_taxonomy_dep",
    poke_interval=3*60,
    timeout=2*60*60,
    aws_conn_id="aws_prod_data",
    bucket_name='5a-datalake-prod',
    bucket_key="dags_execution_logs/{execution_date}/{dependency_dag}.SUCCESS".format(execution_date=last_dep_execution_date, dependency_dag='bietlejuice.enrich_amplitude_partner_taxonomy'),
    dag=main_dag
)

ebdb_dep = S3KeySensor(
    task_id="ebdb_dep",
    poke_interval=3*60,
    timeout=2*60*60,
    aws_conn_id="aws_prod_data",
    bucket_name='5a-datalake-prod',
    bucket_key="dags_execution_logs/{execution_date}/{dependency_dag}.SUCCESS".format(execution_date=last_dep_execution_date, dependency_dag='bietlejuice.ebdb'),
    dag=main_dag
)

docx_dep = S3KeySensor(
    task_id="docx_dep",
    poke_interval=3*60,
    timeout=2*60*60,
    aws_conn_id="aws_prod_data",
    bucket_name='5a-datalake-prod',
    bucket_key="dags_execution_logs/{execution_date}/{dependency_dag}.SUCCESS".format(execution_date=last_dep_execution_date, dependency_dag='bietlejuice.docx'),
    dag=main_dag
)

autodialer_dep = S3KeySensor(
    task_id="autodialer_dep",
    poke_interval=3*60,
    timeout=2*60*60,
    aws_conn_id="aws_prod_data",
    bucket_name='5a-datalake-prod',
    bucket_key="dags_execution_logs/{execution_date}/{dependency_dag}.SUCCESS".format(execution_date=last_dep_execution_date, dependency_dag='bietlejuice.autodialer'),
    dag=main_dag
)

rene_descartes_dep = S3KeySensor(
    task_id="rene_descartes_dep",
    poke_interval=3*60,
    timeout=2*60*60,
    aws_conn_id="aws_prod_data",
    bucket_name='5a-datalake-prod',
    bucket_key="dags_execution_logs/{execution_date}/{dependency_dag}.SUCCESS".format(execution_date=last_dep_execution_date, dependency_dag='bietlejuice.rene_descartes'),
    dag=main_dag
)

godfather_dep = S3KeySensor(
    task_id="godfather_dep",
    poke_interval=3*60,
    timeout=2*60*60,
    aws_conn_id="aws_prod_data",
    bucket_name='5a-datalake-prod',
    bucket_key="dags_execution_logs/{execution_date}/{dependency_dag}.SUCCESS".format(execution_date=last_dep_execution_date, dependency_dag='bietlejuice.godfather'),
    dag=main_dag
)

firestore_dep = S3KeySensor(
    task_id="firestore_dep",
    poke_interval=3*60,
    timeout=2*60*60,
    aws_conn_id="aws_prod_data",
    bucket_name='5a-datalake-prod',
    bucket_key="dags_execution_logs/{execution_date}/{dependency_dag}.SUCCESS".format(execution_date=last_dep_execution_date, dependency_dag='bietlejuice.firestore'),
    dag=main_dag
)

# TODO Recreate tasks flow after the data flow is fully fixed
# xcom_amplitude_task.set_downstream([booking_dag, affiliate_dag])
affiliate_dag.set_upstream([region_dag, user_dag])
[lead_conversion_dag, special_condition_dag] >> house_dag

house_dag >> fact_photo_job

photo_job_dag >> fact_photo_job
amplitude_partner_taxonomy >> partner_dag

trigger_bi_growth_dag_task.set_upstream(
    [condo_dag, partner_dag, house_dag, partner_agent_dag, contract_dag]
)

# new 'supply' flow
listing_flows_dag.set_upstream(
    [
        lead_dag,
        photo_job_dag,
        region_dag,
        user_dag,
        house_dag,
        condo_dag,
        ods_house_listing_flows,
    ]
)

dw_sale_fact_listing_flows_dag.set_upstream(
    [
        lead_dag,
        photo_job_dag,
        region_dag,
        user_dag,
        house_dag,
        condo_dag,
        ods_house_listing_flows,
    ]
)


# finance flow
user_dag.set_downstream([bank_dag, bank_account_dag])
bank_transaction_dag.set_upstream([bank_dag, bank_account_dag])

inspection_dag >> fact_inspection_bookings_task

ods_credit_evaluation_task >> proposal_dag

trigger_bi_growth_dag_task.set_upstream(
    [listing_flows_dag, ods_fact_house_listing_status_task]
)

# Marketing Dependencies Flow
special_condition_dag.set_upstream(
    [amplitude_dep,enrich_amplitude_partner_taxonomy_dep,ebdb_dep,docx_dep,autodialer_dep,rene_descartes_dep,godfather_dep,firestore_dep]
)

lead_conversion_dag.set_upstream(
    [amplitude_dep,enrich_amplitude_partner_taxonomy_dep,ebdb_dep,docx_dep,autodialer_dep,rene_descartes_dep,godfather_dep,firestore_dep]
)


contract_dag.set_upstream(
    [amplitude_dep,enrich_amplitude_partner_taxonomy_dep,ebdb_dep,docx_dep,autodialer_dep,rene_descartes_dep,godfather_dep,firestore_dep]
)

house_dag.set_upstream(
    [amplitude_dep,enrich_amplitude_partner_taxonomy_dep,ebdb_dep,docx_dep,autodialer_dep,rene_descartes_dep,godfather_dep,firestore_dep]
)

region_dag.set_upstream(
    [amplitude_dep,enrich_amplitude_partner_taxonomy_dep,ebdb_dep,docx_dep,autodialer_dep,rene_descartes_dep,godfather_dep,firestore_dep]
)

user_dag.set_upstream(
    [amplitude_dep,enrich_amplitude_partner_taxonomy_dep,ebdb_dep,docx_dep,autodialer_dep,rene_descartes_dep,godfather_dep,firestore_dep]
)

condo_dag.set_upstream(
    [amplitude_dep,enrich_amplitude_partner_taxonomy_dep,ebdb_dep,docx_dep,autodialer_dep,rene_descartes_dep,godfather_dep,firestore_dep]
)

photo_job_dag.set_upstream(
    [amplitude_dep,enrich_amplitude_partner_taxonomy_dep,ebdb_dep,docx_dep,autodialer_dep,rene_descartes_dep,godfather_dep,firestore_dep]
)

lead_dag.set_upstream(
    [amplitude_dep,enrich_amplitude_partner_taxonomy_dep,ebdb_dep,docx_dep,autodialer_dep,rene_descartes_dep,godfather_dep,firestore_dep]
)

ods_fact_house_listing_status_task.set_upstream(
    [amplitude_dep,enrich_amplitude_partner_taxonomy_dep,ebdb_dep,docx_dep,autodialer_dep,rene_descartes_dep,godfather_dep,firestore_dep]
)

amplitude_partner_taxonomy.set_upstream(
    [amplitude_dep,enrich_amplitude_partner_taxonomy_dep,ebdb_dep,docx_dep,autodialer_dep,rene_descartes_dep,godfather_dep,firestore_dep]
)