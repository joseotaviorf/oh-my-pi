"""
Performance table + feed historical perf
this script computes the performance table for yesterday (end of day) and writes the result in S3
"""
from datetime import datetime, timedelta

import pandas as pd
from airflow.models import DAG
from airflow.operators import PythonOperator
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import _logger

from ts_monitoring.helpers import write_to_s3, generate_queries, create_sk_dates
from ts_monitoring.import_data import import_ebdb_contrato_aud, import_invoices
from ts_monitoring.processing import compute_performance_table, format_performance_table

MAIN_DAG_NAME = 'tenantScreening-performance'
MAIN_START_DATE = datetime(2018, 3, 20)
MAIN_SCHEDULE_INTERVAL = timedelta(days=1)
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')# comment for testing without airflow
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
    df_contrato_aud_ebdb = import_ebdb_contrato_aud(client)
    df_payments = import_invoices(client)

    # compute the the raw performance table:
    _logger.info('computing raw performance table')
    performance_table_raw = compute_performance_table(df_contrato_aud_ebdb, df_payments, yesterday)

    # feed the normal performance table (day-1)
    _logger.info('feeding the (normal) performance table')
    performance_table = create_sk_dates(performance_table_raw)
    performance_table = format_performance_table(performance_table)

    write_to_s3(performance_table, 'performance/performance.csv')

    _logger.info('generating perfomance queries')
    athena_ddl, pbi_query = generate_queries(performance_table, 'performance')
    write_to_s3(athena_ddl, 'queries/athena_performance_ddl.txt')
    write_to_s3(pbi_query, 'queries/pbi_performance_query.txt')

    # feed the historical performance table :
    _logger.info('feed the historical performance folder in s3')
    historical_performance_table_raw = performance_table_raw.copy()
    historical_performance_table_raw['date_computation'] = yesterday
    historical_performance_table = create_sk_dates(historical_performance_table_raw)
    historical_performance_table = format_performance_table(historical_performance_table)
    write_to_s3(historical_performance_table,
                'historical_performance/performance' + yesterday.strftime(format='%Y%m%d') + '.csv')

    _logger.info('generating historical perfomance queries')
    athena_ddl, pbi_query = generate_queries(historical_performance_table, 'historical_performance')
    write_to_s3(athena_ddl, 'queries/athena_historicalperformance_ddl.txt')
    write_to_s3(pbi_query, 'queries/pbi_historicalperformance_query.txt')


if __name__ == "__main__":
    daily_performance()

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
    max_active_runs=1
)

dag_daily_performance = PythonOperator(
    dag=dag,
    task_id='daily_performance',
    func_command=daily_performance
)
# flow

daily_performance  # >>
