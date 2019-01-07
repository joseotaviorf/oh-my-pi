import json
from datetime import datetime

import pandas as pd
from airflow.models import DAG
from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.dags.invoice import unit_tests
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl.seu_barriga import SeuBarrigaInvoiceFactory, SeuBarrigaTableEnum

# env vars
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
seu_barriga_invoice_dict = json.loads(env.get_airflow_env_var('seubarriga'))['invoice']

MAIN_DAG_NAME = 'bi-seu_barriga-invoice'
MAIN_START_DATE = datetime(2015, 2, 1, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = '0 0 15 * *'

logger = QuintoAndarLogger(MAIN_DAG_NAME)


# functions
def extract_table(_class, endpoint_suffix, **kwargs):
    _invoice = SeuBarrigaInvoiceFactory.factory(
        _class=_class,
        s3_bucket=s3_bucket,
        api_dict=seu_barriga_invoice_dict,
        execution_date=kwargs['execution_date']
    )

    _result = _invoice.request_data(endpoint_suffix=endpoint_suffix)
    if _class == SeuBarrigaTableEnum.REPORT:
        job_url, status_url = _result[0], _result[1]
        _invoice.wait_for_results(status_url=status_url)

        content = _invoice.request_job_data(job_url=job_url)
        data_frame = _invoice.load_content_to_memory_as_csv(content=content)
        raw_table_name = 'seu_barriga_invoice_report'
    elif _class == SeuBarrigaTableEnum.FINE:
        data_frame = pd.read_json(_result)
        raw_table_name = 'seu_barriga_invoice_fine'
    else:
        logger.error("m=extract_table, _class={}".format(_class))
        raise Exception

    _object = _invoice.convert_df_to_json(data_frame=data_frame)
    _invoice.save_into_s3_raw(
        _object=_object,
        file_path_prefix='raw/seu_barriga/invoice/{}'.format(_invoice._type),
        raw_table_name=raw_table_name
    )
    _object.flush()


def __get_dataframe_from_invoice_result(_invoice, result):
    if len(result) == 0:
        logger.error('m=__get_dataframe_from_invoice_result, msg=result is empty')
        raise Exception

    # fines
    if _invoice._type == 'fine':
        return pd.read_json(result)

    # reports
    job_url, status_url = result[0], result[1]
    _invoice.wait_for_results(status_url=status_url)

    content = _invoice.request_job_data(job_url=job_url)
    return _invoice.load_content_to_memory_as_csv(content=content)


def transform_data(_class, **kwargs):
    _invoice = SeuBarrigaInvoiceFactory.factory(
        _class=_class,
        s3_bucket=s3_bucket,
        api_dict=seu_barriga_invoice_dict,
        execution_date=kwargs['execution_date']
    )

    _invoice.transform_data()


# dags
main_dag = DAG(
    dag_id=MAIN_DAG_NAME,
    default_args={
        'owner': BaseDAG.DEFAULT_OWNER,
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    max_active_runs=1
)


def table_sub_dag(sub_dag_name, **kwargs):
    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    _extract = BaseDAG.build_quintoandar_python_operator(
        task_id='extract_table',
        python_callable=extract_table,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            '_class': kwargs['_class'],
            'endpoint_suffix': kwargs['endpoint_suffix']
        }
    )

    _transform = BaseDAG.build_quintoandar_python_operator(
        task_id='transform_data',
        python_callable=transform_data,
        dag=local_dag,
        provide_context=True,
        op_kwargs={'_class': kwargs['_class']}
    )

    _extract >> _transform

    return local_dag


def unit_tests_sub_dag(sub_dag_name, **kwargs):
    return unit_tests.build(
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
        entity=kwargs['_class']
    )


# operators
report_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='report',
    sub_dag_func=table_sub_dag,
    endpoint_suffix='reports/invoice',
    _class=SeuBarrigaTableEnum.REPORT
)

fine_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='fine',
    sub_dag_func=table_sub_dag,
    endpoint_suffix='invoices/fines',
    _class=SeuBarrigaTableEnum.FINE
)

# unit tests
report_unit_tests_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=unit_tests_sub_dag,
    sub_dag_name='report_unit_tests',
    _class=SeuBarrigaTableEnum.REPORT
)

fine_unit_tests_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=unit_tests_sub_dag,
    sub_dag_name='fine_unit_tests',
    _class=SeuBarrigaTableEnum.FINE
)

# flow
report_sub_dag >> report_unit_tests_dag
fine_sub_dag >> fine_unit_tests_dag
