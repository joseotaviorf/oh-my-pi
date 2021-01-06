from bietlejuice.jobs.composer.base.db.data_lake_metastore_mapping import (
    DataLakeMetastoreMapping,
)
from bietlejuice.jobs.composer.base.spark import BaseSparkContext

spark, sc = BaseSparkContext.spark, BaseSparkContext.sc


class TestDatalakeMetastoreMapping:
    def test_get_all_data_lake_info_for_forno(self):
        # arrange
        env = "forno"
        source = "_my_src_"
        datalake_bucket = "bucket-forno"

        # act
        db_info_dict = DataLakeMetastoreMapping(
            env, source, datalake_bucket
        ).get_all_data_lake_info()

        # assert
        assert db_info_dict == {
            "db_clean_databricks": "datalake__my_src__clean",
            "db_clean_hive": "datalake__my_src__clean",
            "db_clean_path": "s3a://bucket-forno/clean/_my_src_/",
            "db_clean_staging_hive": "datalake__my_src__clean_staging",
            "db_clean_staging_databricks": "datalake__my_src__clean_staging",
            "db_clean_staging_path": "s3a://bucket-forno/clean_staging/_my_src_/",
            "db_raw_hive": "datalake__my_src__raw",
            "db_raw_databricks": "datalake__my_src__raw",
            "db_raw_path": "s3a://bucket-forno/raw/_my_src_/",
            "db_enrich_hive": "datalake__my_src_",
            "db_enrich_databricks": "datalake__my_src_",
            "db_enrich_path": "s3a://bucket-forno/enrich/_my_src_/",
        }

    def test_get_all_data_lake_info_for_prod(self):
        # arrange
        env = "prod"
        source = "_my_src_"
        datalake_bucket = "5a-datalake-prod"

        # act
        db_info_dict = DataLakeMetastoreMapping(
            env, source, datalake_bucket
        ).get_all_data_lake_info()

        # assert
        expected = {
            "db_clean_databricks": "datalake__my_src__clean",
            "db_clean_hive": "datalake__my_src__clean_prod",
            "db_clean_path": "s3a://5a-datalake-prod/clean/_my_src_/",
            "db_clean_staging_hive": "datalake__my_src__clean_staging_prod",
            "db_clean_staging_databricks": "datalake__my_src__clean_staging",
            "db_clean_staging_path": "s3a://5a-datalake-prod/clean_staging/_my_src_/",
            "db_raw_hive": "datalake__my_src__raw_prod",
            "db_raw_databricks": "datalake__my_src__raw",
            "db_raw_path": "s3a://5a-datalake-prod/raw/_my_src_/",
            "db_enrich_hive": "datalake__my_src__prod",
            "db_enrich_databricks": "datalake__my_src_",
            "db_enrich_path": "s3a://5a-datalake-prod/enrich/_my_src_/",
        }
        assert db_info_dict == expected

    def test_get_datalake_info_from_layer(self):
        # arrange
        env = "forno"
        source = "_my_src_"
        datalake_bucket = "bucket-forno"
        layer = "raw"

        # act
        expected_dtb_db_name, expected_db_location, expected_hive_db_name = DataLakeMetastoreMapping(
            env, source, datalake_bucket
        ).get_data_lake_info_from_layer(
            layer
        )

        # assert
        assert expected_dtb_db_name == "datalake__my_src__raw"
        assert expected_db_location == "s3a://bucket-forno/raw/_my_src_/"
        assert expected_hive_db_name == "datalake__my_src__raw"
