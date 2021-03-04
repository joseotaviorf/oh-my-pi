from bietlejuice.jobs.composer.base.db.datalake_metastore_mapping import (
    DatalakeMetastoreMapping,
)
from bietlejuice.jobs.composer.base.spark import BaseSparkContext

spark, sc = BaseSparkContext.spark, BaseSparkContext.sc


class TestDatalakeMetastoreMapping:
    def test_get_all_datalake_info_for_forno(self):
        # arrange
        source = "_my_src_"
        datalake_bucket = "bucket-forno"

        # act
        db_info_dict = DatalakeMetastoreMapping(
            source, datalake_bucket
        ).get_all_datalake_info()

        # assert
        assert db_info_dict == {
            "db_clean_name": "datalake__my_src__clean",
            "db_clean_path": "s3a://bucket-forno/clean/_my_src_/",
            "db_clean_staging_name": "datalake__my_src__clean_staging",
            "db_clean_staging_path": "s3a://bucket-forno/clean_staging/_my_src_/",
            "db_raw_name": "datalake__my_src__raw",
            "db_raw_path": "s3a://bucket-forno/raw/_my_src_/",
            "db_enrich_name": "datalake__my_src_",
            "db_enrich_path": "s3a://bucket-forno/enrich/_my_src_/",
        }

    def test_get_all_datalake_info_for_prod(self):
        # arrange
        source = "_my_src_"
        datalake_bucket = "5a-datalake-prod"

        # act
        db_info_dict = DatalakeMetastoreMapping(
            source, datalake_bucket
        ).get_all_datalake_info()

        # assert
        expected = {
            "db_clean_name": "datalake__my_src__clean",
            "db_clean_path": "s3a://5a-datalake-prod/clean/_my_src_/",
            "db_clean_staging_name": "datalake__my_src__clean_staging",
            "db_clean_staging_path": "s3a://5a-datalake-prod/clean_staging/_my_src_/",
            "db_raw_name": "datalake__my_src__raw",
            "db_raw_path": "s3a://5a-datalake-prod/raw/_my_src_/",
            "db_enrich_name": "datalake__my_src_",
            "db_enrich_path": "s3a://5a-datalake-prod/enrich/_my_src_/",
        }
        assert db_info_dict == expected

    def test_get_datalake_info_from_layer(self):
        # arrange
        source = "_my_src_"
        datalake_bucket = "bucket-forno"
        layer = "raw"

        # act
        expected_db_name, expected_db_location = DatalakeMetastoreMapping(
            source, datalake_bucket
        ).get_datalake_info_from_layer(layer)

        # assert
        assert expected_db_name == "datalake__my_src__raw"
        assert expected_db_location == "s3a://bucket-forno/raw/_my_src_/"
