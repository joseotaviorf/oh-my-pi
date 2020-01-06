from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import BaseSparkContext

spark, sc = BaseSparkContext.spark, BaseSparkContext.sc


class TestDatalakeMetastoreService:
    def test_get_db_info_for_forno(self):
        # arrange
        env = 'forno'
        source = '_my_src_'

        # act
        db_info_dict = DatalakeMetastoreService.get_db_info(env, source)

        # assert
        assert db_info_dict == {
            'db_clean_athena': 'datalake__my_src__clean',
            'db_clean_databricks': 'datalake__my_src__clean',
            'db_clean_path': 's3://datalake.s3.forno.data.quintoandar.com.br/clean/_my_src_/',
            'db_clean_staging_athena': 'datalake__my_src__clean_staging',
            'db_clean_staging_databricks': 'datalake__my_src__clean_staging',
            'db_clean_staging_path': 's3://datalake.s3.forno.data.quintoandar.com.br/clean_staging/_my_src_/',
            'db_raw_athena': 'datalake__my_src__raw',
            'db_raw_databricks': 'datalake__my_src__raw',
            'db_raw_path': 's3://datalake.s3.forno.data.quintoandar.com.br/raw/_my_src_/'
        }

    def test_get_db_info_for_prod(self):
        # arrange
        env = 'prod'
        source = '_my_src_'

        # act
        actual_db_info_dict = DatalakeMetastoreService.get_db_info(env, source)

        # assert
        expected = {
            "db_raw_databricks": "datalake__my_src__raw",
            "db_raw_athena": "datalake__my_src__raw_prod",
            "db_raw_path": "s3://5a-datalake-prod/raw/_my_src_/",
            "db_clean_databricks": "datalake__my_src__clean",
            "db_clean_athena": "datalake__my_src__clean_prod",
            "db_clean_path": "s3://5a-datalake-prod/clean/_my_src_/",
            "db_clean_staging_databricks": "datalake__my_src__clean_staging",
            "db_clean_staging_athena": "datalake__my_src__clean_staging_prod",
            "db_clean_staging_path": "s3://5a-datalake-prod/clean_staging/_my_src_/",
        }
        assert actual_db_info_dict == expected

    def test_get_dw_info_for_forno(self):
        # arrange
        env = 'forno'
        schema = '_my_schema_'

        # act
        actual_dw_info_dict = DatalakeMetastoreService.get_dw_info(env, schema)

        # assert
        expected = {
            'dw_bucket': 'dw.s3.forno.data.quintoandar.com.br',
            'dw_schema_databricks': 'dw__my_schema_',
            'dw_schema_path': 's3://dw.s3.forno.data.quintoandar.com.br/_my_schema_/'
        }
        assert actual_dw_info_dict == expected

    def test_get_dw_info_for_prod(self):
        # arrange
        env = 'prod'
        schema = '_my_schema_'

        # act
        actual_dw_info_dict = DatalakeMetastoreService.get_dw_info(env, schema)

        # assert
        expected = {
            'dw_bucket': '5a-dw-prod',
            'dw_schema_databricks': 'dw__my_schema_',
            'dw_schema_path': 's3://5a-dw-prod/_my_schema_/'
        }
        assert actual_dw_info_dict == expected
