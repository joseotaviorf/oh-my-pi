from qa_python_utils import QuintoAndarLogger

import bietlejuice.jobs.base.new_base_etl as utils
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.dags import SOURCE_QUERIES_DIR
from bietlejuice.jobs.dags.supply_demand_funnel.dim_subdag import DimSubDag

logger = QuintoAndarLogger('LeadConversionSubDag')


class LeadConversionSubDag(DimSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(LeadConversionSubDag, self).__init__(
            bucket=bucket,
            sub_dag_name=sub_dag_name,
            dag_name=dag_name,
            schedule_interval=schedule_interval,
            start_date=start_date,
            table_name='ConversaoLead',
            ods_stg_table_name='lead_conversion'
        )

    def build_lead_conversion(self):
        lead_conversion_dag = self._build_local_dag()
        ods_lead_conversion_task = self.__build_data_tasks(lead_conversion_dag)

        return lead_conversion_dag

    @logger
    def get_lead_conversion_query(self, execution_date, **kwargs):
        file_path = '{}/ebdb/supply_demand_funnel/{}.sql'.format(SOURCE_QUERIES_DIR, self.ods_stg_table_name)
        query = BaseETL.get_query_from_file_name(file_name=file_path)
        query = query.format(max_extraction_date=str(execution_date))

        utils.extract_query_dim_from_ebdb_to_ods(dim_name=self.ods_stg_table_name, bucket=DimSubDag.S3_BUCKET,
                                                 command=query)

    @logger
    def __build_data_tasks(self, dag):
        ods_lead_conversion_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_lead_conversion',
            provide_context=True,
            python_callable=self.get_lead_conversion_query
        )

        return ods_lead_conversion_task
