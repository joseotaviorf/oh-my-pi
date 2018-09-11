from datetime import datetime, timedelta

from airflow.models import DAG
from airflow.operators.quintoandar import QuintoAndarPythonOperator

from bietlejuice.jobs.base.base_etl import EnumDB, BaseETL
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags import DEFAULT_DAG_OWNER
from bietlejuice.jobs.dags.unit_economics import unit_tests
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl.dim_utils import load_dim_from_ods_to_dw

env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS', 'EBDB',
                                 'AWS_SECRET_ACCESS_KEY',
                                 'AWS_ACCESS_KEY_ID',
                                 'AWS_DEFAULT_REGION')
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')

MAIN_DAG_NAME = 'bi-load-property-economics'
MAIN_START_DATE = datetime(2018, 2, 17, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = '@daily'


def materialize_view(_bucket, name):
    table = BaseETL.from_db_query(
        db_enum=EnumDB.BI_ODS,
        query='select * from unit_economics.vw_{};'.format(name)
    )

    table = BaseETL.decode_table(table, 'LATIN-1')
    BaseETL.bulk_insert(
        table=table,
        table_name='unit_economics.{}'.format(name),
        db_enum=EnumDB.BI_ODS,
        encoding='UTF8',
        append=False,
        commit=True,
        bucket_name='{}/raw/ods/{}'.format(_bucket, name)
    )


def unit_tests_sub_dag(sub_dag_name):
    return unit_tests.build(
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )


# create DAG definition
main_dag = DAG(
    dag_id=MAIN_DAG_NAME,
    default_args={
        'owner': DEFAULT_DAG_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    max_active_runs=1
)

base_ticket_task = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='base_ticket_task',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'base_ticket_task'}
)

# Supply
supply_affiliate_bonus_costs = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='supply_affiliate_bonus_costs',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'supply_affiliate_bonus_costs'}
)
supply_mkt_affiliate_campaigns_costs = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='supply_mkt_affiliate_campaigns_costs',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'supply_mkt_affiliate_campaigns_costs'}
)
supply_mkt_owner_campaigns_costs = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='supply_mkt_owner_campaigns_costs',
    execution_timeout=timedelta(hours=3),
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'supply_mkt_owner_campaigns_costs'}
)
supply_mkt_costs = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='supply_mkt_costs',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'supply_mkt_costs'}
)
supply_ops_inside_sales_costs = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='supply_ops_inside_sales_costs',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'supply_ops_inside_sales_costs'}
)
supply_ops_photos_costs = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='supply_ops_photos_costs',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'supply_ops_photos_costs'}
)
supply_ops_costs = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='supply_ops_costs',
    execution_timeout=timedelta(hours=3),
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'supply_ops_costs'}
)
supply_costs = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='supply_costs',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'supply_costs'}
)

# Liquidity
liquidity_ab_agent_hours_costs = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='liquidity_ab_agent_hours_costs',
    execution_timeout=timedelta(hours=3),
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'liquidity_ab_agent_hours_costs'}
)
liquidity_lockbox_costs = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='liquidity_lockbox_costs',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'liquidity_lockbox_costs'}
)
liquidity_mkt_tenant_campaigns_costs = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='liquidity_mkt_tenant_campaigns_costs',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'liquidity_mkt_tenant_campaigns_costs'}
)
liquidity_mkt_costs = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='liquidity_mkt_costs',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'liquidity_mkt_costs'}
)
liquidity_ops_bo_pre_sale_costs = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='liquidity_ops_bo_pre_sale_costs',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'liquidity_ops_bo_pre_sale_costs'}
)
liquidity_ops_cs_pre_sale_costs = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='liquidity_ops_cs_pre_sale_costs',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'liquidity_ops_cs_pre_sale_costs'}
)
liquidity_ops_field_ops_costs = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='liquidity_ops_field_ops_costs',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'liquidity_ops_field_ops_costs'}
)
liquidity_ops_costs = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='liquidity_ops_costs',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'liquidity_ops_costs'}
)
liquidity_costs = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='liquidity_costs',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'liquidity_costs'}
)

# Net Revenue
net_revenue_affiliate_commission_costs = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='net_revenue_affiliate_commission_costs',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'net_revenue_affiliate_commission_costs'}
)
net_revenue_agent_commission_costs = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='net_revenue_agent_commission_costs',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'net_revenue_agent_commission_costs'}
)
net_revenue_commission_costs = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='net_revenue_commission_costs',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'net_revenue_commission_costs'}
)
net_revenue_revenues = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='net_revenue_revenues',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'net_revenue_revenues'}
)
net_revenue_revenues_brokerage_fee = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='net_revenue_revenues_brokerage_fee',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'net_revenue_revenues_brokerage_fee'}
)
net_revenue_revenues_mgmt_fee = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='net_revenue_revenues_mgmt_fee',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'net_revenue_revenues_mgmt_fee'}
)
net_revenue_revenues_brokerage_plus_mgmt_aux = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='net_revenue_revenues_brokerage_plus_mgmt_aux',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'net_revenue_revenues_brokerage_plus_mgmt_aux'}
)
net_revenue_taxes = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='net_revenue_taxes',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'net_revenue_taxes'}
)
net_revenue_taxes_delay_fine = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='net_revenue_taxes_delay_fine',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'net_revenue_taxes_delay_fine'}
)
net_revenue_taxes_sales_tax_iss = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='net_revenue_taxes_sales_tax_iss',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'net_revenue_taxes_sales_tax_iss'}
)
net_revenue_taxes_sales_tax_pis_cofins = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='net_revenue_taxes_sales_tax_pis_cofins',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'net_revenue_taxes_sales_tax_pis_cofins'}
)
net_revenue_costs = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='net_revenue_costs',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'net_revenue_costs'}
)

# Management
mgmt_insurance = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='mgmt_insurance',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'mgmt_insurance'}
)
mgmt_insurance_fee = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='mgmt_insurance_fee',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'mgmt_insurance_fee'}
)
mgmt_insurance_pis_cofins = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='mgmt_insurance_pis_cofins',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'mgmt_insurance_pis_cofins'}
)
mgmt_ops_bo_offboarding_costs = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='mgmt_ops_bo_offboarding_costs',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'mgmt_ops_bo_offboarding_costs'}
)
mgmt_ops_bo_onboarding_costs = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='mgmt_ops_bo_onboarding_costs',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'mgmt_ops_bo_onboarding_costs'}
)
mgmt_ops_bo_ongoing_costs = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='mgmt_ops_bo_ongoing_costs',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'mgmt_ops_bo_ongoing_costs'}
)
mgmt_ops_collection_costs = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='mgmt_ops_collection_costs',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'mgmt_ops_collection_costs'}
)
mgmt_ops_costs = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='mgmt_ops_costs',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'mgmt_ops_costs'}
)
mgmt_ops_cs_post_sale_costs = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='mgmt_ops_cs_post_sale_costs',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'mgmt_ops_cs_post_sale_costs'}
)
mgmt_ops_inspection_costs = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='mgmt_ops_inspection_costs',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'mgmt_ops_inspection_costs'}
)
mgmt_costs = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='mgmt_costs',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'mgmt_costs'}
)

fact_property_economics = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='fact_property_economics',
    python_callable=materialize_view,
    op_kwargs={'_bucket': bucket, 'name': 'fact_property_economics'}
)

load_fact = QuintoAndarPythonOperator(
    dag=main_dag,
    task_id='DW_fact_property_economics',
    python_callable=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'fact_property_economics', 'bucket': bucket, 'insert_dummy': False,
               'schema_source': 'unit_economics'}
)

# Unit tests
unit_tests_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=unit_tests_sub_dag,
    sub_dag_name='unit_tests'
)

# Unit Economics Flow

# base
base_ticket_task >> liquidity_ops_cs_pre_sale_costs
base_ticket_task >> mgmt_ops_collection_costs
base_ticket_task >> mgmt_ops_bo_offboarding_costs
base_ticket_task >> mgmt_ops_bo_onboarding_costs
base_ticket_task >> mgmt_ops_cs_post_sale_costs
base_ticket_task >> mgmt_ops_inspection_costs

# supply
supply_ops_inside_sales_costs >> supply_ops_costs
supply_ops_photos_costs >> supply_ops_costs
supply_mkt_affiliate_campaigns_costs >> supply_mkt_costs
supply_mkt_owner_campaigns_costs >> supply_mkt_costs
supply_mkt_costs >> supply_costs
supply_ops_costs >> supply_costs
supply_affiliate_bonus_costs >> supply_costs

# liquidity
liquidity_mkt_tenant_campaigns_costs >> liquidity_mkt_costs
liquidity_ops_bo_pre_sale_costs >> liquidity_ops_costs
liquidity_ops_cs_pre_sale_costs >> liquidity_ops_costs
liquidity_ops_field_ops_costs >> liquidity_ops_costs
liquidity_ab_agent_hours_costs >> liquidity_costs
liquidity_lockbox_costs >> liquidity_costs
liquidity_mkt_costs >> liquidity_costs
liquidity_ops_costs >> liquidity_costs

# net revenue
net_revenue_affiliate_commission_costs >> net_revenue_commission_costs
net_revenue_agent_commission_costs >> net_revenue_commission_costs
net_revenue_revenues_brokerage_fee >> net_revenue_revenues_brokerage_plus_mgmt_aux
net_revenue_revenues_mgmt_fee >> net_revenue_revenues_brokerage_plus_mgmt_aux
net_revenue_revenues_brokerage_plus_mgmt_aux >> net_revenue_revenues
net_revenue_revenues_brokerage_plus_mgmt_aux >> net_revenue_taxes_sales_tax_iss
net_revenue_revenues_brokerage_plus_mgmt_aux >> net_revenue_taxes_sales_tax_pis_cofins
net_revenue_taxes_sales_tax_iss >> net_revenue_taxes
net_revenue_taxes_sales_tax_pis_cofins >> net_revenue_taxes
net_revenue_taxes_delay_fine >> net_revenue_taxes
net_revenue_taxes >> net_revenue_costs
net_revenue_revenues >> net_revenue_costs
net_revenue_commission_costs >> net_revenue_costs

# management
mgmt_insurance_fee >> mgmt_insurance
mgmt_insurance_pis_cofins >> mgmt_insurance
mgmt_ops_bo_offboarding_costs >> mgmt_ops_costs
mgmt_ops_bo_onboarding_costs >> mgmt_ops_costs
mgmt_ops_bo_ongoing_costs >> mgmt_ops_costs
mgmt_ops_collection_costs >> mgmt_ops_costs
mgmt_ops_cs_post_sale_costs >> mgmt_ops_costs
mgmt_ops_inspection_costs >> mgmt_ops_costs
mgmt_ops_costs >> mgmt_costs
mgmt_insurance >> mgmt_costs

# fact
fact_property_economics.set_upstream([supply_costs, liquidity_costs, net_revenue_costs, mgmt_costs])
fact_property_economics >> unit_tests_dag >> load_fact
