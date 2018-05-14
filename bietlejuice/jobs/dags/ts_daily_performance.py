"""
Performance table
this script computes the performance table for yesterday (end of day) and writes the result in S3
"""
from datetime import datetime

import pandas as pd
from airflow.models import DAG
from airflow.operators import PythonOperator
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import _logger

from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl.ts_monitoring.helpers import create_sk_dates
from bietlejuice.jobs.new_etl.ts_monitoring.helpers import generate_queries
from bietlejuice.jobs.new_etl.ts_monitoring.helpers import write_to_s3
from bietlejuice.jobs.new_etl.ts_monitoring.import_data import import_ebdb_contrato_aud
from bietlejuice.jobs.new_etl.ts_monitoring.import_data import import_ebdb_proposta
from bietlejuice.jobs.new_etl.ts_monitoring.import_data import import_invoices
from bietlejuice.jobs.new_etl.ts_monitoring.processing import compute_performance_table
from bietlejuice.jobs.new_etl.ts_monitoring.processing import format_performance_table

MAIN_DAG_NAME = 'tenantScreening-performance'
MAIN_START_DATE = datetime(2018, 3, 20)
MAIN_SCHEDULE_INTERVAL = '30 3 * * *'
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')  # comment for testing without airflow
from bietlejuice.jobs.dags.util import environment as env
# bucket = '5a-datalake'  # for testing without airflow


def daily_performance():
    """
    computes (and writes in s3) the performance table as if we were at the end of D-1
    :return:
    """
    client = AthenaClient(bucket)
    today = pd.Timestamp(pd.Timestamp.today(tz='Brazil/East').date())
    yesterday = today - pd.to_timedelta(1, unit='days')

    # query athena
    _logger.info('Querying athena')
    df_proposta_ebdb = import_ebdb_proposta(client)  # only to know which ones were decided by us
    df_contrato_aud_ebdb = import_ebdb_contrato_aud(client)
    df_payments = import_invoices(client)

    # select in payments and in contrato_aud only the proposals that were initially screened by us
    proposals_screened_by_5a = df_proposta_ebdb[df_proposta_ebdb.screened_by_5a].index
    df_contrato_aud_ebdb = df_contrato_aud_ebdb[df_contrato_aud_ebdb.proposal_id.isin(proposals_screened_by_5a)]
    contracts_screened_by_5a = df_contrato_aud_ebdb.contract_id.unique()
    df_payments = df_payments[df_payments.contract_id.isin(contracts_screened_by_5a)]

    # compute the the raw performance table:
    _logger.info('computing raw performance table')
    performance_table = compute_performance_table(df_contrato_aud_ebdb, df_payments, yesterday)

    # feed the performance table :
    _logger.info('feed the performance folder in s3')
    performance_table['date_computation'] = yesterday
    performance_table['date_computation_30d_ago'] = yesterday - pd.to_timedelta(30, unit='days')
    performance_table = format_performance_table(performance_table)
    performance_table = create_sk_dates(performance_table)
    write_to_s3(performance_table,
                'performance/performance' + yesterday.strftime(format='%Y%m%d') + '.csv')  # writes an object after internally changing a copy of the object to string

    _logger.info('generating performance queries')
    athena_ddl, pbi_query = generate_queries(performance_table, 'performance')
    write_to_s3(athena_ddl, 'queries/athena_performance_ddl.txt')
    write_to_s3(pbi_query, 'queries/pbi_performance_query.txt')

# if __name__ == "__main__":
#     daily_performance()

# DAG

dag = DAG(
    dag_id=MAIN_DAG_NAME,
    default_args={
        'owner': 'Data Team',
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    max_active_runs=1,
    catchup=False
)

PythonOperator(
    dag=dag,
    task_id='daily_performance',
    python_callable=daily_performance
)
