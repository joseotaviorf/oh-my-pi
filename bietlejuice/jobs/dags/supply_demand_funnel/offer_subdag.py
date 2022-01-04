from datetime import datetime

from qa_python_utils import QuintoAndarLogger

import bietlejuice.jobs.base.new_base_etl as utils
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.dags import SOURCE_QUERIES_DIR
from bietlejuice.jobs.dags.supply_demand_funnel.dim_subdag import DimSubDag

logger = QuintoAndarLogger('OfferSubDag')


class OfferSubDag(DimSubDag):
    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(OfferSubDag, self).__init__(
            bucket=bucket,
            sub_dag_name=sub_dag_name,
            dag_name=dag_name,
            schedule_interval=schedule_interval,
            start_date=start_date,
            table_name='Offer',
            ods_stg_table_name='offer'
        )

    @logger
    def build_offer_with_tests(self):
        offer_dag = self._build_local_dag()

        (offer_to_ods_task, pre_proposal_task, pre_proposta_aud_task,
         staging_dim_offer_task, offer_submitted_events_task) = self.__build_data_tasks(offer_dag)

        tests_tasks = self.build_tests_tasks(
            dag=offer_dag,
            from_file_query=True
        )

        pre_proposal_task >> pre_proposta_aud_task
        staging_dim_offer_task.set_upstream([offer_to_ods_task, pre_proposta_aud_task, offer_submitted_events_task])
        staging_dim_offer_task.set_downstream(tests_tasks)

        return offer_dag

    @logger
    def get_pre_proposal_query(self, **kwargs):
        exec_date = kwargs['execution_date']
        dim = 'pre_proposal'

        file_path = '{}/ebdb/supply_demand_funnel/{}.sql'.format(SOURCE_QUERIES_DIR, dim)
        query = BaseETL.get_query_from_file_name(file_name=file_path)
        query = query.format(str(exec_date))

        utils.extract_query_dim_from_ebdb_to_ods(dim_name=dim, bucket=self.bucket, command=query,
                                                 table_name=None)

    @logger
    def __build_data_tasks(self, dag):
        offer_to_ods_task = BaseDAG.build_python_operator(
            task_id='offer_to_ods',
            dag=dag,
            python_callable=utils.load_athena_query_to_ods,
            op_kwargs={
                'dim_name': 'offer',
                'bucket': self.bucket,
                'fname': 'offer'
            }

        )

        pre_proposal_task = BaseDAG.build_python_operator(
            task_id='ODS_pre_proposal',
            dag=dag,
            provide_context=True,
            python_callable=self.get_pre_proposal_query
        )

        pre_proposta_aud_task = BaseDAG.build_python_operator(
            task_id='ODS_pre_proposal_aud',
            dag=dag,
            python_callable=utils.extract_table_dim_from_ebdb_to_ods,
            op_kwargs={
                'dim_name': 'pre_proposal_AUD',
                'table_name': 'PreProposta_AUD',
                'copy_to_clean': False,
                'bucket': self.bucket
            }
        )

        offer_submitted_events_task = BaseDAG.build_python_operator(
            task_id='ODS_offer_submitted_events',
            dag=dag,
            python_callable=utils.load_athena_file_query_to_ods,
            op_kwargs={
                'table_name': 'offer_submitted_events',
                'file_name': 'extract_offer_submitted_events.sql',
                'bucket': self.bucket
            }
        )

        staging_dim_offer_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='STAGING_dim_offer',
            python_callable=utils.load_dim_from_ods_to_staging,
            op_kwargs={
                'dim_name': 'offer',
                'post_command': "update staging.dim_offer set dt_timestamp = '{}' where sk_offer = -1;".format(
                    datetime.now().strftime('%Y-%m-%d'))
            }
        )

        return (offer_to_ods_task, pre_proposal_task,
                pre_proposta_aud_task, staging_dim_offer_task, offer_submitted_events_task)
