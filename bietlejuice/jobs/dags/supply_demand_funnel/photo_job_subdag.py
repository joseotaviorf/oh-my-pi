from qa_python_utils.default_logger import logger

from bietlejuice.jobs.dags.supply_demand_funnel.dim_subdag import DimSubDag


class PhotoJobSubDag(DimSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(PhotoJobSubDag, self).__init__(
            bucket=bucket,
            sub_dag_name=sub_dag_name,
            dag_name=dag_name,
            schedule_interval=schedule_interval,
            start_date=start_date,
            ebdb_table_name='JobFotografo',
            ods_stg_table_name='photo_job'
        )

    @logger
    def build_photo_job_with_tests(self):
        return self.build_with_tests(source_command='call ebdb.list_photo_job();')
