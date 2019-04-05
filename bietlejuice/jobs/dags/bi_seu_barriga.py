import json
from datetime import datetime

import pandas as pd
from airflow.models import DAG
from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.base.data_frame_service import DataFrameCSVService, DataFrameJsonService
from bietlejuice.jobs.dags.invoice import unit_tests
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl.seu_barriga import SeuBarrigaInvoiceFactory, SeuBarrigaTableEnum

# env vars
s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
seu_barriga_invoice_dict = json.loads(env.get_airflow_env_var('seubarriga'))['invoice']

MAIN_DAG_NAME = 'bi-seu-barriga'
MAIN_START_DATE = datetime(2015, 2, 1, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = '30 3 * * *'

logger = QuintoAndarLogger(MAIN_DAG_NAME)


# functions
def __extract_report_table(data, invoice_obj):
    job_url, status_url = data[0], data[1]
    invoice_obj.wait_for_results(status_url=status_url)

    content = invoice_obj.request_job_data(job_url=job_url)

    df_csv_service = DataFrameCSVService()
    data_frame = df_csv_service.unicode_to_df(csv_content=content)

    raw_table_name = 'seu_barriga_invoice_report'
    return data_frame, raw_table_name


def __extract_fine_table(data):
    return pd.read_json(data), 'seu_barriga_invoice_fine'


def extract_table(class_, endpoint_suffix, **kwargs):
    _invoice = SeuBarrigaInvoiceFactory.factory(
        class_=class_,
        s3_bucket=s3_bucket,
        api_dict=seu_barriga_invoice_dict,
        execution_date=kwargs['execution_date']
    )

    _result = _invoice.request_data(endpoint_suffix=endpoint_suffix)
    if class_ == SeuBarrigaTableEnum.REPORT:
        data_frame, raw_table_name = __extract_report_table(_result, _invoice)
    elif class_ == SeuBarrigaTableEnum.FINE:
        data_frame, raw_table_name = __extract_fine_table(_result)
    else:
        raise RuntimeError('m=extract_table, class_={}'.format(class_))

    __save_data_to_s3_raw(_invoice, data_frame, raw_table_name)


def __save_data_to_s3_raw(invoice_obj, data_frame, raw_table_name):
    df_json_service = DataFrameJsonService(df=data_frame)
    object_ = df_json_service.to_json_bytes()
    invoice_obj.save_into_s3_raw(
        object_=object_,
        file_path_prefix='raw/seu_barriga/invoice/{}'.format(invoice_obj.type_),
        raw_table_name=raw_table_name,
    )
    object_.flush()


def __get_dataframe_from_invoice_result(_invoice, result):
    if len(result) == 0:
        logger.error('m=__get_dataframe_from_invoice_result, msg=result is empty')
        raise Exception

    # fines
    if _invoice.type_ == 'fine':
        return pd.read_json(result)

    # reports
    job_url, status_url = result[0], result[1]
    _invoice.wait_for_results(status_url=status_url)

    content = _invoice.request_job_data(job_url=job_url)
    df_csv_service = DataFrameCSVService()
    return df_csv_service.unicode_to_df(csv_content=content)


def transform_data(class_, **kwargs):
    _invoice = SeuBarrigaInvoiceFactory.factory(
        class_=class_,
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
    max_active_runs=1,
    catchup=False
)


def table_sub_dag(sub_dag_name, endpoint_suffix, class_):
    local_dag = BaseSubDag(
        bucket=s3_bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE
    )._build_local_dag()

    _extract = BaseDAG.build_python_operator(
        task_id='extract_table',
        python_callable=extract_table,
        dag=local_dag,
        provide_context=True,
        op_kwargs={
            'class_': class_,
            'endpoint_suffix': endpoint_suffix
        }
    )

    _transform = BaseDAG.build_python_operator(
        task_id='transform_data',
        python_callable=transform_data,
        dag=local_dag,
        provide_context=True,
        op_kwargs={'class_': class_}
    )

    _extract >> _transform

    return local_dag


def unit_tests_sub_dag(sub_dag_name, class_):
    return unit_tests.build(
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
        entity=class_
    )


# operators
report_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='report',
    sub_dag_func=table_sub_dag,
    endpoint_suffix='reports/invoice',
    class_=SeuBarrigaTableEnum.REPORT
)

fine_sub_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_name='fine',
    sub_dag_func=table_sub_dag,
    endpoint_suffix='invoices/fines',
    class_=SeuBarrigaTableEnum.FINE
)

# unit tests
report_unit_tests_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=unit_tests_sub_dag,
    sub_dag_name='report_unit_tests',
    class_=SeuBarrigaTableEnum.REPORT
)

fine_unit_tests_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=unit_tests_sub_dag,
    sub_dag_name='fine_unit_tests',
    class_=SeuBarrigaTableEnum.FINE
)

# flow
report_sub_dag >> report_unit_tests_dag
fine_sub_dag >> fine_unit_tests_dag
