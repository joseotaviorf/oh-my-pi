from bietlejuice.jobs.composer.base.db.dw_metastore_mapping import DwMetastoreMapping
from bietlejuice.jobs.composer.base.spark import BaseSparkContext

spark, sc = BaseSparkContext.spark, BaseSparkContext.sc


class TestDwMetastoreMapping:
    def test_get_all_dw_info_for_forno(self):
        # arrange
        env = "forno"
        schema = "_my_schema_"
        dw_bucket = "datalake-dw-forno"

        # act
        db_info_dict = DwMetastoreMapping(env, schema, dw_bucket).get_all_dw_info()

        # assert
        assert db_info_dict == {
            "dw_bucket": "datalake-dw-forno",
            "dw_schema_databricks": "dw__my_schema_",
            "dw_schema_path": "s3a://datalake-dw-forno/_my_schema_/",
            "dw_staging_databricks": "dw__my_schema__staging",
            "dw_staging_path": "s3a://datalake-dw-forno/staging/_my_schema_/",
        }

    def test_get_all_dw_info_for_prod(self):
        # arrange
        env = "prod"
        schema = "_my_schema_"
        dw_bucket = "datalake-dw-prod"

        # act
        db_info_dict = DwMetastoreMapping(env, schema, dw_bucket).get_all_dw_info()

        # assert
        expected = {
            "dw_bucket": "datalake-dw-prod",
            "dw_schema_databricks": "dw__my_schema_",
            "dw_schema_path": "s3a://datalake-dw-prod/_my_schema_/",
            "dw_staging_databricks": "dw__my_schema__staging",
            "dw_staging_path": "s3a://datalake-dw-prod/staging/_my_schema_/",
        }
        assert db_info_dict == expected
