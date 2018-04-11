from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_test import BaseTest
from bietlejuice.jobs.base.enum_db import EnumDb
from bietlejuice.jobs.dags import DW_TEST_QUERIES_DIR
from bietlejuice.jobs.new_etl.business_dim_etl import BusinessDimensionETL
from bietlejuice.jobs.new_etl.godfather import GodFather
from qa_python_utils.default_logger import logger

S3_BUCKET = '5a-datalake'
biz_etl = BusinessDimensionETL(S3_BUCKET)


@logger
def __build_local_dag(sub_dag_name, dag_name, schedule_interval, start_date):
    return BaseDAG.build_dag(
        '{}.{}'.format(dag_name, sub_dag_name),
        schedule_interval=schedule_interval,
        start_date=start_date,
    )


@logger
def build(sub_dag_name, dag_name, schedule_interval, start_date):
    """ Main method for building the entire Subdag """
    
    local_dag = __build_local_dag(sub_dag_name, dag_name, schedule_interval, start_date)

    offer_to_s3_task, topic_to_s3_task, offer_to_ods_task, pre_proposal_task, pre_proposta_aud_task, \
    condicao_proposta_task, pre_proposta_condicao_proposta_task, dim_offer_task = __build_data_tasks(
        local_dag)

    tests = __build_test_tasks(local_dag)

    offer_to_ods_task.set_upstream([offer_to_s3_task, topic_to_s3_task])
    pre_proposal_task >> pre_proposta_aud_task >> condicao_proposta_task >> pre_proposta_condicao_proposta_task
    pre_proposta_condicao_proposta_task >> dim_offer_task
    offer_to_ods_task >> dim_offer_task
    dim_offer_task.set_downstream(tests)

    return local_dag


def __to_s3(**kwargs):
    GodFather.to_s3(s3_bucket=S3_BUCKET, table_name=kwargs['table_name'])


def __extract_table_dim_from_ebdb_to_ods(**kwargs):
    biz_etl.extract_table_dim_from_ebdb_to_ods(
        dim_name=kwargs['dim_name'],
        table_name=kwargs['table_name'],
        add_timestamp=False if 'add_timestamp' not in kwargs else kwargs['add_timestamp'],
        copy_to_clean=True if 'copy_to_clean' not in kwargs else kwargs['copy_to_clean']
    )


def __extract_query_dim_from_ebdb_to_ods(**kwargs):
    biz_etl.extract_query_dim_from_ebdb_to_ods(
        dim_name=kwargs['dim_name'],
        command=kwargs['command'],
        table_name=None if 'table_name' not in kwargs else kwargs['table_name']
    )


def __load_athena_raw_query_to_ods(**kwargs):
    biz_etl.load_athena_raw_query_to_ods(
        table_name=kwargs['table_name'],
        query=kwargs['query'],
        append=False if 'append' not in kwargs else kwargs['append']
    )


def __load_dim_from_ods_to_dw(**kwargs):
    biz_etl.load_dim_from_ods_to_dw(
        dim_name=kwargs['dim_name'],
        insert_dummy=True if 'insert_dummy' not in kwargs else kwargs['insert_dummy'],
        is_fact=False if 'is_fact' not in kwargs else kwargs['is_fact'],
        pre_command=None if 'pre_command' not in kwargs else kwargs['pre_command'],
        post_command=None if 'post_command' not in kwargs else kwargs['post_command']
    )


@logger
def __build_data_tasks(local_dag):
    offer_to_s3_task = BaseDAG.get_quintoandar_python_operator(
        task_id='offer_to_s3',
        dag=local_dag,
        func_command=__to_s3,
        op_kwargs={'table_name': 'offer'}
    )

    topic_to_s3_task = BaseDAG.get_quintoandar_python_operator(
        task_id='offer_topic_to_s3',
        dag=local_dag,
        func_command=__to_s3,
        op_kwargs={'table_name': 'topic'}
    )

    offer_to_ods_task = BaseDAG.get_quintoandar_python_operator(
        task_id='offer_to_ods',
        dag=local_dag,
        func_command=__load_athena_raw_query_to_ods,
        op_kwargs={'table_name': 'offer', 'query': """
                                                    select distinct
                                                      eo.id,
                                                      eo.atualizadoem,
                                                      eo.criadoem,
                                                      eo.firestoreid,
                                                      eo.godfatherid,
                                                      eo.originalcondo,
                                                      eo.originalhomeinsurance,
                                                      eo.originaliptu,
                                                      eo.originalrent,
                                                      eo.rent,
                                                      eo.status,
                                                      eo.turn,
                                                      eo.client_id,
                                                      eo.house_id,
                                                      eo.rentflow_id,
                                                      eo.rejectionreason,
                                                      eo.iteration,
                                                      eo.expirationdate,
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

    pre_proposal_task = BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_pre_proposal',
        dag=local_dag,
        func_command=__extract_query_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'pre_proposal', 'command': 'call ebdb.list_preproposta();'}

    )

    pre_proposta_aud_task = BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_pre_proposal_aud',
        dag=local_dag,
        func_command=__extract_table_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'pre_proposal_AUD', 'table_name': 'PreProposta_AUD', 'copy_to_clean': False}
    )

    condicao_proposta_task = BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_condition',
        dag=local_dag,
        func_command=__extract_table_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'condition', 'table_name': 'CondicaoProposta', 'copy_to_clean': False}
    )

    pre_proposta_condicao_proposta_task = BaseDAG.get_quintoandar_python_operator(
        task_id='ODS_pre_proposal_condition',
        dag=local_dag,
        func_command=__extract_table_dim_from_ebdb_to_ods,
        op_kwargs={'dim_name': 'pre_proposal_condition', 'table_name': 'PreProposta_CondicaoProposta',
                   'copy_to_clean': False}
    )

    dim_offer_task = BaseDAG.get_quintoandar_python_operator(
        task_id='DW_dim_offer',
        dag=local_dag,
        func_command=__load_dim_from_ods_to_dw,
        op_kwargs={'dim_name': 'offer'}
    )

    return offer_to_s3_task, topic_to_s3_task, offer_to_ods_task, pre_proposal_task, pre_proposta_aud_task, \
           condicao_proposta_task, pre_proposta_condicao_proposta_task, dim_offer_task


def __test_file_query(**kwargs):
    BaseTest.test_file_query(
        file_path=kwargs['file_path'],
        enum_db=kwargs['enum_db'],
        assertion=kwargs['assertion']
    )


@logger
def __build_test_tasks(local_dag):
    # FIXME: change to get_quintoandar_python_operator after testing
    test_status_task = BaseDAG.get_python_operator(
        dag=local_dag,
        task_id='TEST_dim_offer_status',
        func_command=__test_file_query,
        op_kwargs={'file_path': '{}/dim_offer_status.sql'.format(DW_TEST_QUERIES_DIR), 'enum_db': EnumDb.BI_DW,
                   'assertion': None}
    )

    return [test_status_task]
