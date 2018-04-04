"""
Historical performance (Batch compute)
todo get start and end by parameter of the script
the end date should not be past the date where the invoices and contracts have been updated
first ever computable date : 20180206
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

MAIN_DAG_NAME = 'tenantScreening-historical_performance'
MAIN_START_DATE = datetime(2018, 3, 20)
MAIN_SCHEDULE_INTERVAL = timedelta(days=1)
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')  # comment for testing without airflow
#bucket = '5a-datalake'  # for testing without airflow
start_date = '20180208'  # todo : parameters of airflow?
end_date = '20180401'


def historical_performance():
    """
    computes the performance table of every day between start_date and end_date (included)
    and writes them as separate files in an s3 folder.
    NB : for each day we pretend to be at the end of that day.
    :return:
    """
    client = AthenaClient(bucket)

    # query athena
    df_contrato_aud_ebdb = import_ebdb_contrato_aud(client)
    df_payments = import_invoices(client)

    # compute the performance table for each date in date_range
    date_range = pd.date_range(start=pd.to_datetime(start_date), end=pd.to_datetime(end_date))
    for date in date_range:
        _logger.info(date)
        performance_table = compute_performance_table(df_contrato_aud_ebdb, df_payments, date)
        performance_table['date_computation'] = date
        performance_table = create_sk_dates(performance_table)
        performance_table = format_performance_table(performance_table)
        write_to_s3(performance_table,
                    'historical_performance/performance' + date.strftime(format='%Y%m%d') + '.csv')

    athena_ddl, pbi_query = generate_queries(performance_table, 'historical_performance')
    write_to_s3(athena_ddl, 'queries/athena_historicalperformance_ddl.txt')
    write_to_s3(pbi_query, 'queries/pbi_historicalperformance_query.txt')


if __name__ == "__main__":
    historical_performance()

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
    task_id='historical_performance',
    func_command=historical_performance
)
# flow

historical_performance  # >>
