"""
Originacao Table
"""
from datetime import datetime, timedelta

import pandas as pd
from airflow.models import DAG
from airflow.operators import PythonOperator
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import _logger

from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl.ts_monitoring.processing import compute_originacao_table, format_originacao_table
from bietlejuice.jobs.new_etl.ts_monitoring.import_data import \
    import_ebdb_proposta, \
    import_sortinghat_proposal, \
    import_sortinghat_proponent, \
    import_api, \
    import_ebdb_contrato
from bietlejuice.jobs.new_etl.ts_monitoring.helpers import write_to_s3, generate_queries, create_sk_dates

MAIN_DAG_NAME = 'tenantScreening-originacao'
MAIN_START_DATE = datetime(2018, 3, 20)
MAIN_SCHEDULE_INTERVAL = '30 3 * * *'

bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')  # comment for testing without airflow


# bucket = '5a-datalake'#for testing without airflow
# from jobs.dags.util import environment as env

def originacao():
    """
    computes the originacao table as if we were at the end of D-1 and writes it in s3
    :return:
    """
    client = AthenaClient(bucket)
    today = pd.Timestamp(pd.Timestamp.today(tz='Brazil/East').date())
    yesterday = today - pd.to_timedelta(1, unit='days')

    # query athena
    _logger.info('Querying athena')
    df_proposta_ebdb = import_ebdb_proposta(client)
    df_proposal_sh = import_sortinghat_proposal(client)
    df_proponents_of_proposal = import_sortinghat_proponent(client)
    df_api_last = import_api(client)
    df_contrato_ebdb = import_ebdb_contrato(client)

    # compute the last version of the originacao table
    _logger.info('Compute last version of originacao')
    output_originacao = compute_originacao_table(df_proposta_ebdb,
                                                 df_contrato_ebdb,
                                                 df_proposal_sh,
                                                 df_proponents_of_proposal,
                                                 df_api_last)
    _logger.info('Format and write originacao in s3')
    output_originacao = format_originacao_table(output_originacao)
    output_originacao = create_sk_dates(output_originacao)

    write_to_s3(output_originacao, 'originacao/originacao.csv')  # writes an object after internally changing a copy of the object to string


    athena_ddl, pbi_query = generate_queries(output_originacao, 'originacao')
    write_to_s3(athena_ddl, 'queries/athena_originacao_ddl.txt')
    write_to_s3(pbi_query, 'queries/pbi_originacao_query.txt')


# if __name__ == "__main__":
#     originacao()

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
    task_id='originacao',
    python_callable=originacao
)
