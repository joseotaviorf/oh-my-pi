from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.dags import SOURCE_QUERIES_DIR
from bietlejuice.jobs.dags.supply_demand_funnel.dim_subdag import DimSubDag

logger = QuintoAndarLogger('PhotoJobSubDag')


class PhotoJobSubDag(DimSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(PhotoJobSubDag, self).__init__(
            bucket=bucket,
            sub_dag_name=sub_dag_name,
            dag_name=dag_name,
            schedule_interval=schedule_interval,
            start_date=start_date,
            table_name='JobFotografo',
            ods_stg_table_name='photo_job'
        )

    @logger
    def build_photo_job_with_tests(self):
        file_path = '{}/ebdb/supply_demand_funnel/{}.sql'.format(SOURCE_QUERIES_DIR, 'photo_job')
        query = BaseETL.get_query_from_file_name(file_name=file_path)

        return self.build_with_tests(source_command=query)
