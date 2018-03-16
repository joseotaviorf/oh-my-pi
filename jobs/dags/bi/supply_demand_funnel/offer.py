from jobs.base.base_dag import BaseDAG
from jobs.base.base_test import BaseTest
from jobs.base.enum_db import EnumDb
from jobs.dags.bi.__init__ import DW_TEST_QUERIES_DIR
from jobs.new_etl.business_dim_etl import BusinessDimensionETL
from jobs.new_etl.godfather import GodFather
from qa_python_utils.default_logger import logger


class OfferSubDag(object):
    def __init__(self, s3_bucket):
        self.s3_bucket = s3_bucket
        self.biz_etl = BusinessDimensionETL(s3_bucket)

    @staticmethod
    @logger
    def __build_local_dag(sub_dag_name, dag_name, schedule_interval, start_date):
        return BaseDAG.build_dag(
            '{}.{}'.format(dag_name, sub_dag_name),
            schedule_interval=schedule_interval,
            start_date=start_date,
        )

    @logger
    def build(self, sub_dag_name, dag_name, schedule_interval, start_date):
        local_dag = OfferSubDag.__build_local_dag(sub_dag_name, dag_name, schedule_interval, start_date)

        condicao_proposta_task, dim_offer_task, offer_to_ods_task, offer_to_s3_task, pre_proposal_task, \
        pre_proposta_aud_task, pre_proposta_condicao_proposta_task, topic_to_s3_task = self.__build_data_tasks(
            local_dag)

        tests = self.__build_test_tasks(local_dag)

        offer_to_ods_task.set_upstream([offer_to_s3_task, topic_to_s3_task])
        pre_proposal_task >> pre_proposta_aud_task >> condicao_proposta_task >> pre_proposta_condicao_proposta_task
        pre_proposta_condicao_proposta_task >> dim_offer_task
        offer_to_ods_task >> dim_offer_task
        dim_offer_task.set_downstream(tests)

        return local_dag

    @logger
    def __build_data_tasks(self, local_dag):
        offer_to_s3_task = BaseDAG.get_quintoandar_python_operator(
            task_id='offer_to_s3',
            dag=local_dag,
            func_command=GodFather.to_s3(s3_bucket=self.s3_bucket, table_name='offer')
        )
        topic_to_s3_task = BaseDAG.get_quintoandar_python_operator(
            task_id='offer_topic_to_s3',
            dag=local_dag,
            func_command=GodFather.to_s3(s3_bucket=self.s3_bucket, table_name='topic')
        )
        offer_to_ods_task = BaseDAG.get_quintoandar_python_operator(
            task_id='offer_to_ods',
            dag=local_dag,
            func_command=self.biz_etl.load_athena_raw_query_to_ods(
                table_name='offer',
                query="""
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
            )
        )
        pre_proposal_task = BaseDAG.get_quintoandar_python_operator(
            task_id='ODS_pre_proposal',
            dag=local_dag,
            func_command=self.biz_etl.extract_query_dim_from_ebdb_to_ods(
                dim_name='pre_proposal',
                command='call ebdb.list_preproposta();'
            )
        )
        pre_proposta_aud_task = BaseDAG.get_quintoandar_python_operator(
            task_id='ODS_pre_proposal_aud',
            dag=local_dag,
            func_command=self.biz_etl.extract_query_dim_from_ebdb_to_ods(
                dim_name='pre_proposal_AUD',
                table_name='PreProposta_AUD',
                copy_to_clean=False
            )
        )
        condicao_proposta_task = BaseDAG.get_quintoandar_python_operator(
            task_id='ODS_condition',
            dag=local_dag,
            func_command=self.biz_etl.extract_query_dim_from_ebdb_to_ods(
                dim_name='condition',
                table_name='CondicaoProposta',
                copy_to_clean=False
            )
        )
        pre_proposta_condicao_proposta_task = BaseDAG.get_quintoandar_python_operator(
            task_id='ODS_pre_proposal_condition',
            dag=local_dag,
            func_command=self.biz_etl.extract_query_dim_from_ebdb_to_ods(
                dim_name='pre_proposal_condition',
                table_name='PreProposta_CondicaoProposta',
                copy_to_clean=False
            )
        )
        dim_offer_task = BaseDAG.get_quintoandar_python_operator(
            task_id='DW_dim_offer',
            dag=local_dag,
            func_command=self.biz_etl.load_dim_from_ods_to_dw(
                dim_name='offer'
            )
        )

        return condicao_proposta_task, dim_offer_task, offer_to_ods_task, offer_to_s3_task, pre_proposal_task, \
               pre_proposta_aud_task, pre_proposta_condicao_proposta_task, topic_to_s3_task

    @logger
    def __build_test_tasks(self, local_dag):
        # FIXME: change to get_quintoandar_python_operator after testing
        test_status_task = BaseDAG.get_python_operator(
            dag=local_dag,
            task_id='TEST_dim_offer_status',
            func_command=BaseTest.test_file_query(
                file_path='{}/dim_offer_status.sql'.format(DW_TEST_QUERIES_DIR),
                enum_db=EnumDb.BI_DW,
                assertion=None)
        )

        return [test_status_task]
