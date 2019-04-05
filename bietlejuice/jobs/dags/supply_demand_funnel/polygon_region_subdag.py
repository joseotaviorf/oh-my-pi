from qa_python_utils import QuintoAndarLogger

import bietlejuice.jobs.base.new_base_etl as utils
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.dags import SOURCE_QUERIES_DIR
from bietlejuice.jobs.dags.supply_demand_funnel.dim_subdag import DimSubDag

logger = QuintoAndarLogger('PolygonRegionSubDag')


class PolygonRegionSubDag(DimSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(PolygonRegionSubDag, self).__init__(
            bucket=bucket,
            sub_dag_name=sub_dag_name,
            dag_name=dag_name,
            schedule_interval=schedule_interval,
            start_date=start_date,
            table_name='PoligonoRegiao',
            ods_stg_table_name='polygon_region'
        )

    @logger
    def build_polygon_region_with_tests(self):
        polygon_region_dag = self._build_local_dag()
        ods_polygon_region_task = self.__build_data_tasks(polygon_region_dag)

        return polygon_region_dag

    @logger
    def get_house_query(self):
        file_path = '{}/ebdb/supply_demand_funnel/{}.sql'.format(SOURCE_QUERIES_DIR, self.ods_stg_table_name)
        query = BaseETL.get_query_from_file_name(file_name=file_path)

        utils.extract_query_dim_from_ebdb_to_ods(
            dim_name=self.ods_stg_table_name,
            bucket=DimSubDag.S3_BUCKET,
            command=query,
            table_name=self.ods_stg_table_name
        )

    @logger
    def __build_data_tasks(self, dag):
        ods_polygon_region_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_polygon_region',
            python_callable=self.get_house_query
        )

        return ods_polygon_region_task
