from datetime import datetime

import airflow.utils.helpers as airflow_helpers
import bietlejuice.jobs.base.new_base_etl as utils
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.dags import SOURCE_QUERIES_DIR
from bietlejuice.jobs.dags.supply_demand_funnel.dim_subdag import DimSubDag
from qa_python_utils import QuintoAndarLogger

logger = QuintoAndarLogger('AffiliateSubDag')


class AffiliateSubDag(DimSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(AffiliateSubDag, self).__init__(
            bucket=bucket,
            sub_dag_name=sub_dag_name,
            dag_name=dag_name,
            schedule_interval=schedule_interval,
            start_date=start_date,
            ebdb_table_name='DadosAfiliado',
            ods_stg_table_name='user_affiliate'
        )

    def build_affiliate_with_tests(self):
        affiliate_dag = self._build_local_dag()

        ods_affiliate_task, staging_dim_affiliate_task, dw_dim_affiliate_task = self.__build_data_tasks(affiliate_dag)

        tests_tasks = self.build_tests_tasks(affiliate_dag)

        airflow_helpers.chain(ods_affiliate_task, staging_dim_affiliate_task)
        staging_dim_affiliate_task.set_downstream(tests_tasks)
        dw_dim_affiliate_task.set_upstream(tests_tasks)

        return affiliate_dag

    @logger
    def __move_query_results_from_ebdb_to_ods(self, dim_name, **kwargs):
        file_path = '{}/ebdb/supply_demand_funnel/{}.sql'.format(SOURCE_QUERIES_DIR, dim_name)
        query = str(BaseETL.get_query_from_file_name(file_name=file_path))
        query = query.format(str(kwargs.get('execution_date')))

        utils.extract_query_dim_from_ebdb_to_ods(dim_name=dim_name, bucket=DimSubDag.S3_BUCKET, command=query,
                                                 table_name=None)

    @logger
    def __build_data_tasks(self, dag):
        ods_affiliate = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_user_affiliate',
            provide_context=True,
            python_callable=self.__move_query_results_from_ebdb_to_ods,
            op_kwargs={
                'dim_name': self.ods_stg_table_name
            }
        )

        staging_dim_affiliate_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='STAGING_dim_user_affiliate',
            python_callable=utils.load_dim_from_ods_to_staging,
            op_kwargs={
                'dim_name': self.ods_stg_table_name,
                'post_command': "update staging.dim_user_affiliate set ts_load = '{}' where sk_user_affiliate = -1;".format(
                    datetime.now().strftime('%Y-%m-%d'))
            }
        )

        dw_dim_affiliate_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='DW_dim_user_affiliate',
            python_callable=utils.load_dim_from_staging_to_dw,
            op_kwargs={
                'dim_name': self.ods_stg_table_name,
                'bucket': DimSubDag.S3_BUCKET
            }
        )

        return ods_affiliate, staging_dim_affiliate_task, dw_dim_affiliate_task
