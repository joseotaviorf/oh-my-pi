import json
from datetime import datetime

import airflow.utils.helpers as airflow_helpers
from airflow.operators.bash_operator import BashOperator
from qa_python_utils import QuintoAndarLogger

import bietlejuice.jobs.base.new_base_etl as utils
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDB
from bietlejuice.jobs.dags import SOURCE_QUERIES_DIR, ODS_QUERIES_DIR
from bietlejuice.jobs.dags.supply_demand_funnel.dim_subdag import DimSubDag
from bietlejuice.jobs.dags.util import environment as env

s3_bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
looker_bucket = env.get_airflow_env_var('looker_bucket')
GOOGLE_S_A_CREDENTIALS = json.loads(env.get_airflow_env_var('GOOGLE_SERVICE_ACCOUNT_CREDENTIALS'))
GOOGLE_API_SCOPE = env.get_airflow_env_var('GOOGLE_API_SCOPE')
GOOGLE_SHEETS_FILES = json.loads(env.get_airflow_env_var('BI_AUX_REGIAO_GOOGLE_SHEETS_FILES'))


logger = QuintoAndarLogger('RegionSubDag')


class RegionSubDag(DimSubDag):

    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date):
        super(RegionSubDag, self).__init__(
            bucket=bucket,
            sub_dag_name=sub_dag_name,
            dag_name=dag_name,
            schedule_interval=schedule_interval,
            start_date=start_date,
            table_name='Regiao',
            ods_stg_table_name='region'
        )

    @logger
    def build_region_with_tests(self):
        region_dag = self._build_local_dag()

        (agent_region,
         region,
         polygon_region,
         save_polygons_geojson_to_local,
         convert_polygons_geojson_to_topojson,
         upload_polygons_topojson_to_s3,
         dim_region) = self.__build_data_tasks(region_dag)

        tests_tasks = self.build_tests_tasks(region_dag)

        save_polygons_geojson_to_local.set_upstream([dim_region, polygon_region])
        airflow_helpers.chain(save_polygons_geojson_to_local,
                              convert_polygons_geojson_to_topojson,
                              upload_polygons_topojson_to_s3)
        dim_region.set_upstream([agent_region, region])
        dim_region.set_downstream(tests_tasks)

        return region_dag

    @logger
    def __build_data_tasks(self, dag):
        agent_region = BaseDAG.build_python_operator(
            task_id='ODS_agent_region',
            dag=dag,
            python_callable=utils.extract_table_dim_from_ebdb_to_ods,
            op_kwargs={
                'dim_name': 'agent_region',
                'table_name': 'DadosAgente_Regiao',
                'copy_to_clean': False,
                'bucket': self.bucket
            },
            trigger_rule='all_done'
        )

        region = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_region',
            python_callable=self.__extract_query_dim_from_ebdb_to_ods,
            op_kwargs={
                'dim_name': 'region',
                'bucket': self.bucket
            },
            trigger_rule='all_done'
        )

        polygon_region = BaseDAG.build_python_operator(
            dag=dag,
            task_id='ODS_polygon_region',
            python_callable=self.get_polygon_region_query
        )

        subregion_polygons_filename_prefix = '5a_subregion_polygons'
        save_polygons_geojson_to_local = BaseDAG.build_python_operator(
            dag=dag,
            task_id='save_polygons_geojson_to_local',
            python_callable=self.save_polygons_geojson_to_local,
            op_kwargs={
                'subregion_polygons_filename_prefix': subregion_polygons_filename_prefix
            }
        )

        convert_polygons_geojson_to_topojson = BashOperator(
            dag=dag,
            task_id='convert_polygons_geojson_to_topojson',
            bash_command='geo2topo -o /tmp/{0}.topojson /tmp/{0}.geojson'.format(
                subregion_polygons_filename_prefix),
        )

        upload_polygons_topojson_to_s3 = BaseDAG.build_python_operator(
            dag=dag,
            task_id='upload_polygons_topojson_to_s3',
            python_callable=self.upload_polygons_topojson_to_s3,
            op_kwargs={
                'subregion_polygons_filename_prefix': subregion_polygons_filename_prefix
            }
        )

        dim_region = BaseDAG.build_python_operator(
            dag=dag,
            task_id='STAGING_dim_region',
            python_callable=utils.load_dim_from_ods_to_staging,
            op_kwargs={
                'dim_name': 'region',
                'post_command': "update staging.dim_region set dt_timestamp = '{}', region_code = '-1', region_code_deprecated = '-1' where sk_region = -1;".format(
                    datetime.now().strftime('%Y-%m-%d'))
            }
        )

        return (agent_region,
                region,
                polygon_region,
                save_polygons_geojson_to_local,
                convert_polygons_geojson_to_topojson,
                upload_polygons_topojson_to_s3,
                dim_region
                )

    @logger
    def __extract_query_dim_from_ebdb_to_ods(self, dim_name, bucket):
        command = BaseETL.get_query_from_file_name(
            file_name='{0}/ebdb/supply_demand_funnel/{1}.sql'.format(SOURCE_QUERIES_DIR,
                                                                     dim_name))

        utils.extract_query_dim_from_ebdb_to_ods(dim_name=dim_name, bucket=bucket,
                                                 command=command)

    @logger
    def get_polygon_region_query(self):
        dim = 'polygon_region'

        file_path = '{}/ebdb/supply_demand_funnel/{}.sql'.format(SOURCE_QUERIES_DIR,
                                                                 dim)

        query = BaseETL.get_query_from_file_name(file_name=file_path)
        utils.extract_query_dim_from_ebdb_to_ods(dim_name=dim,
                                                 bucket=self.bucket,
                                                 command=query,
                                                 table_name=None)

    @logger
    def __get_polygons_geojson_data(self):
        command = BaseETL.get_query_from_file_name(
            file_name='{0}/polygons_geojson.sql'.format(ODS_QUERIES_DIR))

        logger.info('m=__get_polygons_geojson_data, msg=querying geojson from db')
        return BaseETL.from_db_query(
            db_enum=EnumDB.BI_ODS,
            query=command
        )

    @logger
    def save_polygons_geojson_to_local(self, subregion_polygons_filename_prefix):
        table_view = self.__get_polygons_geojson_data()
        if not table_view:
            logger.error('m=save_polygons_geojson_to_local, msg=table_view is empty or None')

        with open('/tmp/{}.geojson'.format(subregion_polygons_filename_prefix),
                  'w') as fp:
            logger.info(
                'm=save_polygons_geojson_to_local, msg=saving table_view as json to /tmp')
            json.dump(table_view[1][0], fp)

    @logger
    def upload_polygons_topojson_to_s3(self, subregion_polygons_filename_prefix):
        logger.info('m=upload_polygons_topojson_to_s3, msg=saving history file')

        filename = '{}.topojson'.format(subregion_polygons_filename_prefix)
        dir_path = '/tmp'
        bucket_folder_path_prefix = '{}/subregion_polygons'.format(looker_bucket)
        today = datetime.now().date()

        BaseETL.file_to_s3(
            filename=filename,
            dir_path=dir_path,
            bucket_folder_path='{}/year={}/month={}/day={}'.format(
                bucket_folder_path_prefix,
                today.strftime('%Y'),
                today.strftime('%m'),
                today.strftime('%d')
            )
        )

        logger.info('m=upload_polygons_topojson_to_s3, msg=saving latest file')
        BaseETL.file_to_s3(
            filename=filename,
            dir_path=dir_path,
            bucket_folder_path=bucket_folder_path_prefix
        )
