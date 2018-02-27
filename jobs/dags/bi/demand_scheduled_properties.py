from datetime import datetime

from jobs.dags.bi.base_dag import BaseDAG
from jobs.dags.util import environment as env
from jobs.new_etl.business_dim_etl import BusinessDimensionETL
from jobs.new_etl.godfather import GodFather

env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS', 'EBDB', 'GODFATHER')
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')

biz_etl = BusinessDimensionETL(bucket, datetime.now())

MAIN_DAG_NAME = 'bi-demand-scheduled-properties'
MAIN_START_DATE = datetime(2018, 1, 1, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = '0 3 * * *'

# create main DAG definition
main_dag = BaseDAG.build_dag(
    dag_id=MAIN_DAG_NAME,
    description='ETL pipeline for the entire demand funnel',
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL
)


def godfather_to_s3(**kwargs):
    GodFather.to_s3(bucket, kwargs['table_name'])


def godfather_to_ods(**kwargs):
    GodFather.to_ods(kwargs['table_name'])


def extract_query_dim_from_ebdb_to_ods(**kwargs):
    biz_etl.extract_query_dim_from_ebdb_to_ods(
        dim_name=kwargs['dim_name'],
        command=kwargs['command'],
        table_name=None if 'table_name' not in kwargs else kwargs['table_name']
    )


def extract_table_dim_from_ebdb_to_ods(**kwargs):
    biz_etl.extract_table_dim_from_ebdb_to_ods(
        dim_name=kwargs['dim_name'],
        table_name=kwargs['table_name'],
        add_timestamp=False if 'add_timestamp' not in kwargs else kwargs['add_timestamp'],
        copy_to_clean=True if 'copy_to_clean' not in kwargs else kwargs['copy_to_clean']
    )


def load_athena_file_query_to_ods(**kwargs):
    biz_etl.load_athena_file_query_to_ods(
        table_name=kwargs['table_name'],
        file_name=kwargs['file_name'],
        append=False if 'append' not in kwargs else kwargs['append']
    )


def load_athena_raw_query_to_ods(**kwargs):
    biz_etl.load_athena_raw_query_to_ods(
        table_name=kwargs['table_name'],
        query=kwargs['query'],
        append=False if 'append' not in kwargs else kwargs['append']
    )


def load_dim_from_ods_to_dw(**kwargs):
    biz_etl.load_dim_from_ods_to_dw(
        dim_name=kwargs['dim_name'],
        insert_dummy=True if 'insert_dummy' not in kwargs else kwargs['insert_dummy'],
        is_fact=False if 'is_fact' not in kwargs else kwargs['is_fact'],
        pre_command=None if 'pre_command' not in kwargs else kwargs['pre_command'],
        post_command=None if 'post_command' not in kwargs else kwargs['post_command']
    )


def ods_sub_dag(sub_dag_name):
    local_dag = BaseDAG.build_dag(
        '{}.{}'.format(MAIN_DAG_NAME, sub_dag_name),
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    BaseDAG.get_python_operator(
        task_id='ODS_contract',
        dag=local_dag,
        func_command=extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'contract', 'command': 'call ebdb.list_contrato();'}
    )

    BaseDAG.get_python_operator(
        task_id='ODS_negotiation',
        dag=local_dag,
        func_command=extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'negotiation', 'command': 'call ebdb.list_negociacao();'}
    )

    offer_to_s3_task = BaseDAG.get_python_operator(
        task_id='offer_to_s3',
        dag=local_dag,
        func_command=godfather_to_s3,
        op_kwargs={'table_name': 'offer'}
    )

    topic_to_s3_task = BaseDAG.get_python_operator(
        task_id='offer_topic_to_s3',
        dag=local_dag,
        func_command=godfather_to_s3,
        op_kwargs={'table_name': 'topic'}
    )

    offer_to_ods_task = BaseDAG.get_python_operator(
        task_id='offer_to_ods',
        dag=local_dag,
        func_command=load_athena_raw_query_to_ods,
        op_kwargs={'table_name': 'offer', 'query': """
                                                    select distinct
                                                        eo.*,
                                                        go.type,
                                                        go.first_sent_at,
                                                        go.last_sent_at,
                                                        gt.type as topic_type
                                                    from datalake_raw.ebdb_offer eo
                                                    join datalake_raw.godfather_offer go
                                                        on eo.godfatherid = go.id
                                                    left join datalake_raw.godfather_topic gt
                                                        on gt.offer_id = go.id
                                                    ;
                                                    """
                   }
    )

    pre_proposal_task = BaseDAG.get_python_operator(
        task_id='ODS_pre_proposal',
        dag=local_dag,
        func_command=extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'pre_proposal', 'command': 'call ebdb.list_preproposta();'}
    )

    pre_proposta_aud_task = BaseDAG.get_python_operator(
        task_id='ODS_pre_proposal_aud',
        dag=local_dag,
        func_command=extract_table_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'pre_proposal_AUD', 'table_name': 'PreProposta_AUD', 'copy_to_clean': False}
    )

    condicao_proposta_task = BaseDAG.get_python_operator(
        task_id='ODS_condition',
        dag=local_dag,
        func_command=extract_table_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'condition', 'table_name': 'CondicaoProposta', 'copy_to_clean': False}
    )

    pre_proposta_condicao_proposta_task = BaseDAG.get_python_operator(
        task_id='ODS_pre_proposal_condition',
        dag=local_dag,
        func_command=extract_table_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'pre_proposal_condition', 'table_name': 'PreProposta_CondicaoProposta',
                   'copy_to_clean': False}
    )

    BaseDAG.get_python_operator(
        task_id='ODS_proposal',
        dag=local_dag,
        func_command=extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'proposal', 'command': 'call ebdb.list_proposta();'}
    )

    BaseDAG.get_python_operator(
        task_id='ODS_booking',
        dag=local_dag,
        func_command=extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'booking', 'command': 'call ebdb.list_agendamento();'}
    )

    property_visit_information_task = BaseDAG.get_python_operator(
        task_id='ODS_property_visit_information',
        dag=local_dag,
        func_command=load_athena_file_query_to_ods,
        op_kwargs={'table_name': 'property_visit_information', 'append': True,
                   'file_name': 'property_visit_information.sql'}
    )

    visits_task = BaseDAG.get_python_operator(
        task_id='ODS_visits',
        dag=local_dag,
        func_command=extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'visit', 'command': 'call ebdb.list_visita();'}
    )

    BaseDAG.get_python_operator(
        task_id='ODS_rental_flow',
        dag=local_dag,
        func_command=extract_table_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'rental_flow', 'table_name': 'FluxoLocacao', 'copy_to_clean': False}
    )

    BaseDAG.get_python_operator(
        task_id='ODS_region',
        dag=local_dag,
        func_command=extract_table_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'agent_region', 'table_name': 'DadosAgente_Regiao', 'copy_to_clean': False}
    )

    property_visit_information_task >> visits_task
    offer_to_ods_task.set_upstream([offer_to_s3_task, topic_to_s3_task])
    pre_proposal_task >> pre_proposta_aud_task >> condicao_proposta_task >> pre_proposta_condicao_proposta_task

    return local_dag


def dw_sub_dag(sub_dag_name):
    local_dag = BaseDAG.build_dag(
        '{}.{}'.format(MAIN_DAG_NAME, sub_dag_name),
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )

    BaseDAG.get_python_operator(
        task_id='DW_dim_contract',
        dag=local_dag,
        func_command=load_dim_from_ods_to_dw,
        op_kwargs={'dim_name': 'contract'}
    )

    BaseDAG.get_python_operator(
        task_id='DW_dim_negotiation',
        dag=local_dag,
        func_command=load_dim_from_ods_to_dw,
        op_kwargs={'dim_name': 'negotiation'}
    )

    BaseDAG.get_python_operator(
        task_id='DW_dim_pre_proposal',
        dag=local_dag,
        func_command=load_dim_from_ods_to_dw,
        op_kwargs={'dim_name': 'pre_proposal'}
    )

    BaseDAG.get_python_operator(
        task_id='DW_dim_proposal',
        dag=local_dag,
        func_command=load_dim_from_ods_to_dw,
        op_kwargs={'dim_name': 'proposal'}
    )

    booking_media_sources_task = BaseDAG.get_python_operator(
        task_id='ODS_booking_media_sources',
        dag=local_dag,
        func_command=load_athena_file_query_to_ods,
        op_kwargs={'table_name': 'booking_media_sources', 'file_name': 'extract_booking_media_sources.sql'}
    )

    dim_booking_task = BaseDAG.get_python_operator(
        task_id='DW_dim_booking',
        dag=local_dag,
        func_command=load_dim_from_ods_to_dw,
        op_kwargs={'dim_name': 'booking',
                   'post_command': 'update dim_booking set visit_follow_up = null where visit_follow_up = ""'}
    )

    BaseDAG.get_python_operator(
        task_id='DW_dim_visits',
        dag=local_dag,
        func_command=load_dim_from_ods_to_dw,
        op_kwargs={'dim_name': 'visit'}
    )

    booking_media_sources_task >> dim_booking_task

    return local_dag


ods_property_scheduling_task = BaseDAG.get_python_operator(
    task_id='ODS_liquidity_property_scheduling',
    dag=main_dag,
    func_command=extract_query_dim_from_ebdb_to_ods,
    op_kwargs={'dim_name': 'property_scheduling', 'command': 'call ebdb.list_property_scheduling();'}
)

fact_property_scheduling_task = BaseDAG.get_python_operator(
    task_id='DW_fact_liquidity_property_scheduling',
    dag=main_dag,
    func_command=load_dim_from_ods_to_dw,
    op_kwargs={'dim_name': 'liquidity_property_scheduling', 'is_fact': True, 'insert_dummy': False}
)

# flow
BaseDAG.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=ods_sub_dag,
    sub_dag_name='ODS'
) >> ods_property_scheduling_task >> BaseDAG.get_sub_dag_operator(
    dag=main_dag,
    sub_dag_func=dw_sub_dag,
    sub_dag_name='DW'
) >> fact_property_scheduling_task
