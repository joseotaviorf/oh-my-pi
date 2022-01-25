from qa_python_utils import QuintoAndarLogger

import bietlejuice.jobs.base.new_base_etl as utils
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.dags.supply_demand_funnel.dim_subdag import DimSubDag

logger = QuintoAndarLogger('ContractSubDag')


class ContractSubDag(DimSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(ContractSubDag, self).__init__(
            bucket=bucket,
            sub_dag_name=sub_dag_name,
            dag_name=dag_name,
            schedule_interval=schedule_interval,
            start_date=start_date,
            table_name='Contrato',
            ods_stg_table_name='contract'
        )

    @logger
    def build_contract_with_tests(self):
        contract_dag = self._build_local_dag()

        (contract_task, staging_dim_contract_task) = self.__build_data_tasks(contract_dag)

        # TODO: put tests back to flow
        # tests_tasks = self.build_tests_tasks(contract_dag)

        contract_task >> staging_dim_contract_task
        # staging_dim_contracttask.set_downstream(tests_tasks)
        # dim_contract.set_upstream(tests_tasks)

        return contract_dag

    @logger
    def __build_data_tasks(self, dag):
        contract_task = BaseDAG.build_python_operator(
            task_id='ODS_contract',
            dag=dag,
            python_callable=utils.load_athena_file_query_to_ods,
            op_kwargs={
                'table_name': 'contract',
                'file_name': 'contract/contract.sql',
                'bucket': self.bucket
            }
        )
        staging_dim_contract_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='STAGING_dim_contract',
            python_callable=utils.load_dim_from_ods_to_staging,
            op_kwargs={
                'dim_name': 'contract'
            }
        )

        return (contract_task, staging_dim_contract_task)
