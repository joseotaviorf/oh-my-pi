from bietlejuice.jobs.composer.base.db import DWMetastoreService
from bietlejuice.jobs.composer.base.spark import BaseSparkContext

spark, sc = BaseSparkContext.spark, BaseSparkContext.sc


class TestDWMetastoreService:
    def test_get_dw_info_for_forno(self):
        # arrange
        env = "forno"
        schema = "_my_schema_"
        dw_bucket = "dw.s3.forno.data.quintoandar.com.br"

        # act
        actual_dw_info_dict = DWMetastoreService.get_dw_info(env, schema, dw_bucket)

        # assert
        expected = {
            "dw_bucket": "dw.s3.forno.data.quintoandar.com.br",
            "dw_staging_databricks": "dw__my_schema__staging",
            "dw_schema_databricks": "dw__my_schema_",
            "dw_staging_path": "s3://dw.s3.forno.data.quintoandar.com.br/staging/_my_schema_/",
            "dw_schema_path": "s3://dw.s3.forno.data.quintoandar.com.br/_my_schema_/",
        }
        assert actual_dw_info_dict == expected

    def test_get_dw_info_for_prod(self):
        # arrange
        env = "prod"
        schema = "_my_schema_"
        dw_bucket = "5a-dw-prod"

        # act
        actual_dw_info_dict = DWMetastoreService.get_dw_info(env, schema, dw_bucket)

        # assert
        expected = {
            "dw_bucket": "5a-dw-prod",
            "dw_schema_databricks": "dw__my_schema_",
            "dw_staging_databricks": "dw__my_schema__staging",
            "dw_staging_path": "s3://5a-dw-prod/staging/_my_schema_/",
            "dw_schema_path": "s3://5a-dw-prod/_my_schema_/",
        }
        assert actual_dw_info_dict == expected
