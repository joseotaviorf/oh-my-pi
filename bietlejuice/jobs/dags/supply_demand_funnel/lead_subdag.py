from datetime import datetime

import airflow.utils.helpers as airflow_helpers
import bietlejuice.jobs.base.new_base_etl as utils
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.dags import SOURCE_QUERIES_DIR
from bietlejuice.jobs.dags.supply_demand_funnel.dim_subdag import DimSubDag
from qa_python_utils import QuintoAndarLogger

logger = QuintoAndarLogger('LeadSubDag')


class LeadSubDag(DimSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(LeadSubDag, self).__init__(
            bucket=bucket,
            sub_dag_name=sub_dag_name,
            dag_name=dag_name,
            schedule_interval=schedule_interval,
            start_date=start_date,
            table_name='Lead',
            ods_stg_table_name='lead'
        )

    def build_lead_with_tests(self):
        lead_dag = self._build_local_dag()

        ods_reprocessed_lead_task, ods_lead_score_factor_task, ods_lead_task, staging_dim_lead_task, \
            dw_dim_lead_task = self.__build_data_tasks(lead_dag)

        tests_tasks = self.build_tests_tasks(lead_dag)

        ods_lead_task.set_upstream([ods_lead_score_factor_task, ods_reprocessed_lead_task])
        airflow_helpers.chain(ods_lead_task, staging_dim_lead_task)
        staging_dim_lead_task.set_downstream(tests_tasks)
        dw_dim_lead_task.set_upstream(tests_tasks)

        return lead_dag

    @logger
    def __move_query_results_from_ebdb_to_ods(self, dim_name, **kwargs):
        file_path = '{}/ebdb/supply_demand_funnel/{}.sql'.format(SOURCE_QUERIES_DIR, dim_name)
        query = str(BaseETL.get_query_from_file_name(file_name=file_path))
        query = query.format(str(kwargs.get('execution_date')))

        utils.extract_query_dim_from_ebdb_to_ods(dim_name=dim_name, bucket=DimSubDag.S3_BUCKET, command=query,
                                                 table_name=None)

    @logger
    def __build_data_tasks(self, dag):
        ods_reprocessed_lead_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_reprocessed_lead',
            python_callable=self.__move_query_results_from_ebdb_to_ods,
            op_kwargs={
                'dim_name': 'reprocessed_lead'
            }
        )

        ods_lead_score_factor_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_lead_score_factor',
            python_callable=utils.load_athena_file_query_to_ods,
            op_kwargs={
                'table_name': 'lead_score_factor',
                'file_name': 'lead/lead_score_factor.sql',
                'bucket': DimSubDag.S3_BUCKET
            }
        )

        ods_lead = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_lead',
            provide_context=True,
            python_callable=self.__move_query_results_from_ebdb_to_ods,
            op_kwargs={
                'dim_name': 'lead'
            }
        )

        staging_dim_lead_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='STAGING_dim_lead',
            python_callable=utils.load_dim_from_ods_to_staging,
            op_kwargs={
                'dim_name': 'lead',
                'post_command': "update staging.dim_lead set load_timestamp = '{}' where sk_lead = -1;".format(
                    datetime.now().strftime('%Y-%m-%d'))
            }
        )

        dw_dim_lead_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='DW_dim_lead',
            python_callable=utils.load_dim_from_staging_to_dw,
            op_kwargs={
                'dim_name': 'lead',
                'bucket': DimSubDag.S3_BUCKET
            }
        )

        return ods_reprocessed_lead_task, ods_lead_score_factor_task, ods_lead, staging_dim_lead_task, dw_dim_lead_task
