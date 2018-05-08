from datetime import datetime

from qa_python_utils.default_logger import logger

import bietlejuice.jobs.base.new_base_etl as utils
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.supply_demand_funnel.dim_subdag import DimSubDag
from bietlejuice.jobs.new_etl.godfather import GodFather


class OfferSubDag(DimSubDag):
    S3_BUCKET = '5a-datalake'

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(OfferSubDag, self).__init__(
            bucket=bucket,
            sub_dag_name=sub_dag_name,
            dag_name=dag_name,
            schedule_interval=schedule_interval,
            start_date=start_date,
            ebdb_table_name='regiao',
            ods_stg_table_name='region'
        )

    @logger
    def build_offer_with_tests(self):
        region_dag = self._build_local_dag()

        (offer_to_s3_task, topic_to_s3_task, offer_to_ods_task, pre_proposal_task, pre_proposta_aud_task,
         condicao_proposta_task, pre_proposta_condicao_proposta_task, staging_dim_offer_task,
         dim_offer_task) = self.__build_data_tasks(region_dag)

        tests_tasks = self.build_tests_tasks(region_dag)

        offer_to_ods_task.set_upstream([offer_to_s3_task, topic_to_s3_task])
        pre_proposal_task >> pre_proposta_aud_task >> condicao_proposta_task >> pre_proposta_condicao_proposta_task
        staging_dim_offer_task.set_upstream([offer_to_ods_task, pre_proposta_condicao_proposta_task])
        staging_dim_offer_task.set_downstream(tests_tasks)
        dim_offer_task.set_upstream(tests_tasks)

        return region_dag

    @staticmethod
    def __to_s3(**kwargs):
        GodFather.to_s3(s3_bucket=OfferSubDag.S3_BUCKET, table_name=kwargs['table_name'])

    @logger
    def __build_data_tasks(self, dag):
        offer_to_s3_task = BaseDAG.get_quintoandar_python_operator(
            task_id='offer_to_s3',
            dag=dag,
            func_command=OfferSubDag.__to_s3,
            op_kwargs={
                'table_name': 'offer'
            }
        )

        topic_to_s3_task = BaseDAG.get_quintoandar_python_operator(
            task_id='offer_topic_to_s3',
            dag=dag,
            func_command=OfferSubDag.__to_s3,
            op_kwargs={
                'table_name': 'topic'
            }
        )

        offer_to_ods_task = BaseDAG.get_quintoandar_python_operator(
            task_id='offer_to_ods',
            dag=dag,
            func_command=utils.load_athena_query_to_ods,
            op_kwargs={
                'dim_name': 'offer',
                'bucket': DimSubDag.S3_BUCKET,
                'fname': 'offer'
            }

        )

        pre_proposal_task = BaseDAG.get_quintoandar_python_operator(
            task_id='ODS_pre_proposal',
            dag=dag,
            func_command=utils.extract_query_dim_from_ebdb_to_ods,
            op_kwargs={
                'dim_name': 'pre_proposal',
                'command': 'call ebdb.list_preproposta();',
                'bucket': DimSubDag.S3_BUCKET
            }

        )

        pre_proposta_aud_task = BaseDAG.get_quintoandar_python_operator(
            task_id='ODS_pre_proposal_aud',
            dag=dag,
            func_command=utils.extract_table_dim_from_ebdb_to_ods,
            op_kwargs={
                'dim_name': 'pre_proposal_AUD',
                'table_name': 'PreProposta_AUD',
                'copy_to_clean': False,
                'bucket': DimSubDag.S3_BUCKET
            }
        )

        condicao_proposta_task = BaseDAG.get_quintoandar_python_operator(
            task_id='ODS_condition',
            dag=dag,
            func_command=utils.extract_table_dim_from_ebdb_to_ods,
            op_kwargs={
                'dim_name': 'condition',
                'table_name': 'CondicaoProposta',
                'copy_to_clean': False,
                'bucket': DimSubDag.S3_BUCKET
            }
        )

        pre_proposta_condicao_proposta_task = BaseDAG.get_quintoandar_python_operator(
            task_id='ODS_pre_proposal_condition',
            dag=dag,
            func_command=utils.extract_table_dim_from_ebdb_to_ods,
            op_kwargs={
                'dim_name': 'pre_proposal_condition',
                'table_name': 'PreProposta_CondicaoProposta',
                'copy_to_clean': False,
                'bucket': DimSubDag.S3_BUCKET
            }
        )

        staging_dim_offer_task = BaseDAG.get_quintoandar_python_operator(
            dag=dag,
            task_id='STAGING_dim_offer',
            func_command=utils.load_dim_from_ods_to_staging,
            op_kwargs={
                'dim_name': 'offer',
                'post_command': "update staging.dim_offer set dt_timestamp = '{}' where sk_offer = -1;".format(
                    datetime.now().strftime('%Y-%m-%d'))
            }
        )

        dim_offer_task = BaseDAG.get_quintoandar_python_operator(
            task_id='DW_dim_offer',
            dag=dag,
            func_command=utils.load_dim_from_staging_to_dw,
            op_kwargs={
                'dim_name': 'offer'
            }
        )

        return (offer_to_s3_task, topic_to_s3_task, offer_to_ods_task, pre_proposal_task, pre_proposta_aud_task,
                condicao_proposta_task, pre_proposta_condicao_proposta_task, staging_dim_offer_task, dim_offer_task)
