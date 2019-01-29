import bietlejuice.jobs.base.new_base_etl as utils
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.supply_demand_funnel.dim_subdag import DimSubDag
from qa_python_utils import QuintoAndarLogger

logger = QuintoAndarLogger('BankTransactionSubDag')


class BankTransactionSubDag(DimSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(BankTransactionSubDag, self).__init__(
            bucket=bucket,
            sub_dag_name=sub_dag_name,
            dag_name=dag_name,
            schedule_interval=schedule_interval,
            start_date=start_date,
            ebdb_table_name='OperacaoContaCorrente',
            ods_stg_table_name='bank_transaction'
        )

    @logger
    def build_bank_transaction(self):
        bank_transaction_dag = self._build_local_dag()

        ods_bank_transaction_task, fact_bank_transaction_task = self.__build_data_tasks(bank_transaction_dag)

        ods_bank_transaction_task >> fact_bank_transaction_task

        return bank_transaction_dag

    @logger
    def __build_data_tasks(self, dag):
        ods_bank_transaction_task = BaseDAG.build_quintoandar_python_operator(
            task_id='ODS_bank_transaction',
            dag=dag,
            python_callable=utils.extract_table_dim_from_ebdb_to_ods,
            op_kwargs={
                'dim_name': self.ods_stg_table_name,
                'table_name': self.ebdb_table_name,
                'copy_to_clean': False,
                'bucket': DimSubDag.S3_BUCKET
            }
        )

        fact_bank_transaction_task = BaseDAG.build_quintoandar_python_operator(
            dag=dag,
            task_id='DW_fact_bank_transaction',
            python_callable=self.__build_fact_bank_transaction,
            op_kwargs={
                'fact_name': 'bank_transaction',
                'schema_dest': 'bank'
            }
        )

        return ods_bank_transaction_task, fact_bank_transaction_task

    @logger
    def __build_fact_bank_transaction(self, fact_name, schema_dest):
        # process to staging
        utils.load_dim_from_ods_to_staging(dim_name=fact_name, is_fact=True)
        # staging to DW
        utils.load_dim_from_staging_to_dw(dim_name=fact_name, bucket=self.bucket, is_fact=True, schema_dest=schema_dest)
