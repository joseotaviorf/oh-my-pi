from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.dags import SOURCE_QUERIES_DIR
from bietlejuice.jobs.dags.supply_demand_funnel.dim_subdag import DimSubDag

logger = QuintoAndarLogger('InspectionSubDag')


class InspectionSubDag(DimSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(InspectionSubDag, self).__init__(
            bucket=bucket,
            sub_dag_name=sub_dag_name,
            dag_name=dag_name,
            schedule_interval=schedule_interval,
            start_date=start_date,
            table_name='Vistoria',
            ods_stg_table_name='inspection'
        )

    @logger
    def build_inspection_with_tests(self):
        file_path = '{}/ebdb/supply_demand_funnel/{}.sql'.format(SOURCE_QUERIES_DIR, self.ods_stg_table_name)
        query = BaseETL.get_query_from_file_name(file_name=file_path)

        return self.build_with_tests(source_command=query, table_name=self.ods_stg_table_name, remove_redshift_load=True)
