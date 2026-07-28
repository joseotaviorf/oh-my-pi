import pytest

from bietlejuice.base.db.datalake_metastore_service import DatalakeMetastoreService
from bietlejuice.base.spark.base_spark import BaseSparkContext

spark, sc = BaseSparkContext.spark, BaseSparkContext.sc


class TestDatalakeMetastoreService:
    def test_get_db_info_for_forno(self):
        # arrange
        env = "forno"
        source = "_my_src_"
        datalake_bucket = "5a-datalake-forno"

        # act
        db_info_dict = DatalakeMetastoreService.get_db_info(
            env, source, datalake_bucket
        )

        # assert
        assert db_info_dict == {
            "db_clean_athena": "datalake__my_src__clean",
            "db_clean_databricks": "datalake__my_src__clean",
            "db_clean_path": "s3://5a-datalake-forno/clean/_my_src_/",
            "db_clean_staging_athena": "datalake__my_src__clean_staging",
            "db_clean_staging_databricks": "datalake__my_src__clean_staging",
            "db_clean_staging_path": "s3://5a-datalake-forno/clean_staging/_my_src_/",
            "db_raw_athena": "datalake__my_src__raw",
            "db_raw_databricks": "datalake__my_src__raw",
            "db_raw_path": "s3://5a-datalake-forno/raw/_my_src_/",
            "db_enrich_athena": "datalake__my_src_",
            "db_enrich_databricks": "datalake__my_src_",
            "db_enrich_path": "s3://5a-datalake-forno/enrich/_my_src_/",
        }

    def test_get_db_info_for_prod(self):
        # arrange
        env = "prod"
        source = "_my_src_"
        datalake_bucket = "5a-datalake-prod"

        # act
        actual_db_info_dict = DatalakeMetastoreService.get_db_info(
            env, source, datalake_bucket
        )

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
            "db_enrich_athena": "datalake__my_src__prod",
            "db_enrich_databricks": "datalake__my_src_",
            "db_enrich_path": "s3://5a-datalake-prod/enrich/_my_src_/",
        }
        assert actual_db_info_dict == expected

    @pytest.mark.parametrize(
        "source",
        ("ops_finance", "ops_ss", "ops_public", "forrent_postcontract"),
    )
    def test_get_db_info_governed_schema_drops_datalake_prefix(self, source):
        # arrange: a schema following the new naming convention (no datalake_ prefix)
        env = "forno"
        datalake_bucket = "5a-datalake-forno"

        # act
        db_info_dict = DatalakeMetastoreService.get_db_info(
            env, source, datalake_bucket
        )

        # assert: names drop the prefix; the S3 path is unchanged (never carried it)
        assert db_info_dict["db_enrich_databricks"] == source
        assert db_info_dict["db_enrich_athena"] == source
        assert db_info_dict["db_clean_databricks"] == f"{source}_clean"
        assert (
            db_info_dict["db_enrich_path"] == f"s3://5a-datalake-forno/enrich/{source}/"
        )
