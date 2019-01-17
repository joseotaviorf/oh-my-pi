from datetime import datetime

import bietlejuice.jobs.base.new_base_etl as utils
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.supply_demand_funnel.dim_subdag import DimSubDag
from qa_python_utils import QuintoAndarLogger

logger = QuintoAndarLogger('FinanceSubDag')


class FinanceSubDag(DimSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(FinanceSubDag, self).__init__(
            bucket=bucket,
            sub_dag_name=sub_dag_name,
            dag_name=dag_name,
            schedule_interval=schedule_interval,
            start_date=start_date,
            ebdb_table_name='Banco',
            ods_stg_table_name='bank'
        )

    @logger
    def build_finance_with_tests(self):
        finance_dag = self._build_local_dag()

        ods_bank_task, dim_bank_staging_task, dim_bank_dw_task = self.__build_data_tasks(finance_dag)

        tests_tasks = self.build_tests_tasks(finance_dag)

        ods_bank_task >> dim_bank_staging_task
        dim_bank_staging_task.set_downstream(tests_tasks)
        dim_bank_dw_task.set_upstream(tests_tasks)

        return finance_dag

    @logger
    def __build_data_tasks(self, dag):
        ods_bank_task = BaseDAG.build_quintoandar_python_operator(
            task_id='ODS_bank',
            dag=dag,
            python_callable=utils.extract_table_dim_from_ebdb_to_ods,
            op_kwargs={
                'dim_name': 'bank',
                'table_name': 'Banco',
                'copy_to_clean': False,
                'bucket': DimSubDag.S3_BUCKET
            }
        )

        dim_bank_staging_task = BaseDAG.build_quintoandar_python_operator(
            dag=dag,
            task_id='STAGING_dim_bank',
            python_callable=utils.load_dim_from_ods_to_staging,
            op_kwargs={
                'dim_name': 'bank',
                'post_command': "update staging.dim_bank set ts_load = '{}' where sk_bank = -1;".format(
                    datetime.now().strftime('%Y-%m-%d'))
            }
        )

        dim_bank_dw_task = BaseDAG.build_quintoandar_python_operator(
            dag=dag,
            task_id='DW_dim_bank',
            python_callable=utils.load_dim_from_staging_to_dw,
            op_kwargs={
                'dim_name': 'bank',
                'bucket': DimSubDag.S3_BUCKET,
                'schema_dest': 'bank'
            }
        )

        return ods_bank_task, dim_bank_staging_task, dim_bank_dw_task
