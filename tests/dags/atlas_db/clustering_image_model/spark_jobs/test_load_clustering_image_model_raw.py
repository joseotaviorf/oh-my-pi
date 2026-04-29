import sys
import unittest
from datetime import date
from unittest.mock import MagicMock, patch, call

mock_pyspark = MagicMock()
sys.modules["pyspark"] = mock_pyspark
sys.modules["pyspark.conf"] = MagicMock()
sys.modules["pyspark.sql"] = MagicMock()
sys.modules["pyspark.sql.functions"] = MagicMock()
sys.modules["pyspark.sql.types"] = MagicMock()
sys.modules["pyspark.sql.dataframe"] = MagicMock()
sys.modules["pyspark.context"] = MagicMock()

sys.modules["bietlejuice.base.db"] = MagicMock()
sys.modules["bietlejuice.base.spark"] = MagicMock()
sys.modules["bietlejuice.clients.db_clients"] = MagicMock()
sys.modules["bietlejuice.loaders"] = MagicMock()
sys.modules["bietlejuice.loaders.s3_loader"] = MagicMock()
sys.modules["bietlejuice.services.metastore_services"] = MagicMock()
sys.modules["quintoandar_logger"] = MagicMock()

from dags.atlas_db.clustering_image_model.spark_jobs.load_clustering_image_model_raw import (  # noqa: E402
    _fs_entry_is_directory,
    parse_folder_date,
    normalize_matchmaker_columns,
    load_dataframe_into_datalake,
)

EXPECTED_COLUMNS = [
    "condo",
    "sourcenameid_anchor",
    "sourcenameid_pair",
    "unit_anchor",
    "unit_pair",
    "building_anchor",
    "building_pair",
    "photos_anchor",
    "photos_pair",
    "similarity",
    "ypred",
    "check_metadata",
    "ypred_using_metadata",
    "db_to_filter",
    "model_metadata",
    "dt_model",
]


class TestParseFolderDate(unittest.TestCase):

    def test_valid_date(self):
        self.assertEqual(parse_folder_date("2026-04-15"), date(2026, 4, 15))

    def test_trailing_slash(self):
        self.assertEqual(parse_folder_date("2026-04-15/"), date(2026, 4, 15))

    def test_invalid_string(self):
        self.assertIsNone(parse_folder_date("not-a-date"))

    def test_empty_string(self):
        self.assertIsNone(parse_folder_date(""))

    def test_partial_date(self):
        self.assertIsNone(parse_folder_date("2026-04"))

    def test_extra_segments(self):
        self.assertIsNone(parse_folder_date("2026-04-15-extra"))


class TestFsEntryIsDirectory(unittest.TestCase):

    def test_boolean_true(self):
        entry = MagicMock(spec=[])
        entry.isDir = True
        self.assertTrue(_fs_entry_is_directory(entry))

    def test_boolean_false(self):
        entry = MagicMock(spec=[])
        entry.isDir = False
        self.assertFalse(_fs_entry_is_directory(entry))

    def test_callable_true(self):
        entry = MagicMock()
        entry.isDir = MagicMock(return_value=True)
        self.assertTrue(_fs_entry_is_directory(entry))

    def test_callable_false(self):
        entry = MagicMock()
        entry.isDir = MagicMock(return_value=False)
        self.assertFalse(_fs_entry_is_directory(entry))

    def test_no_isdir_attribute(self):
        entry = object()
        self.assertFalse(_fs_entry_is_directory(entry))


class TestNormalizeMatchmakerColumns(unittest.TestCase):

    def _make_df(self, columns):
        df = MagicMock()
        df.columns = list(columns)
        df.withColumnRenamed.return_value = df
        return df

    def test_renames_matchmaker_columns(self):
        df = self._make_df(["listing_id_anchor", "listing_id_pair", "similarity"])
        result = normalize_matchmaker_columns(df)
        df.withColumnRenamed.assert_any_call("listing_id_anchor", "sourcenameid_anchor")
        df.withColumnRenamed.assert_any_call("listing_id_pair", "sourcenameid_pair")
        self.assertEqual(df.withColumnRenamed.call_count, 2)
        self.assertIs(result, df)

    def test_already_legacy_names_no_rename(self):
        df = self._make_df(["sourcenameid_anchor", "sourcenameid_pair", "similarity"])
        normalize_matchmaker_columns(df)
        df.withColumnRenamed.assert_not_called()

    def test_no_matching_columns_no_rename(self):
        df = self._make_df(["condo", "similarity", "ypred"])
        normalize_matchmaker_columns(df)
        df.withColumnRenamed.assert_not_called()

    def test_both_old_and_new_present_skips_rename(self):
        df = self._make_df([
            "listing_id_anchor",
            "sourcenameid_anchor",
            "listing_id_pair",
            "sourcenameid_pair",
        ])
        normalize_matchmaker_columns(df)
        df.withColumnRenamed.assert_not_called()


class TestLoadDataframeIntoDatalake(unittest.TestCase):

    MODULE_PATH = (
        "dags.atlas_db.clustering_image_model"
        ".spark_jobs.load_clustering_image_model_raw"
    )

    def setUp(self):
        self.mock_df = MagicMock()
        self.mock_df.columns = EXPECTED_COLUMNS

        self.partition_cols = ["year", "month", "day"]
        self.environment = "prod"
        self.datalake_bucket = "5a-datalake-prod"
        self.source = "clustering_image_model"
        self.raw_table_name = "clustering_image"

    @patch(f"{MODULE_PATH}.SparkMetastoreService")
    @patch(f"{MODULE_PATH}.SparkMetastoreLoader")
    @patch(f"{MODULE_PATH}.S3Loader")
    @patch(f"{MODULE_PATH}.SparkClient")
    @patch(f"{MODULE_PATH}.DatalakeMetastoreService")
    @patch(f"{MODULE_PATH}.SparkTableStorageFormat")
    def test_calls_services_with_correct_params(
        self,
        mock_format,
        mock_datalake_svc,
        mock_spark_client,
        mock_s3_loader_cls,
        mock_metastore_loader_cls,
        mock_metastore_svc_cls,
    ):
        mock_datalake_svc.get_db_info.return_value = {
            "db_raw_databricks": "datalake_clustering_image_model_raw",
            "db_raw_path": "s3://5a-datalake-prod/raw/clustering_image_model/",
        }
        mock_format.DEFAULT_RAW = "parquet_raw_format"

        mock_s3_loader = MagicMock()
        mock_s3_loader_cls.return_value = mock_s3_loader

        mock_metastore_svc = MagicMock()
        mock_metastore_svc_cls.return_value = mock_metastore_svc

        mock_metastore_loader = MagicMock()
        mock_metastore_loader_cls.return_value = mock_metastore_loader

        load_dataframe_into_datalake(
            datalake_bucket=self.datalake_bucket,
            df=self.mock_df,
            environment=self.environment,
            partition_cols=self.partition_cols,
            raw_table_name=self.raw_table_name,
            source=self.source,
        )

        mock_datalake_svc.get_db_info.assert_called_once_with(
            env=self.environment,
            source=self.source,
            bucket=self.datalake_bucket,
        )

        mock_metastore_svc.create_database.assert_called_once_with(
            database_name="datalake_clustering_image_model_raw"
        )

        mock_s3_loader.load_df.assert_called_once_with(
            df=self.mock_df,
            s3_path="s3://5a-datalake-prod/raw/clustering_image_model/clustering_image",
            format_options="parquet_raw_format",
            partitions=self.partition_cols,
            max_records_per_file=250000,
            compression="gzip",
        )

        mock_metastore_loader.update_metastore.assert_called_once_with(
            df=self.mock_df,
            database_name="datalake_clustering_image_model_raw",
            table_name=self.raw_table_name,
            format_options="parquet_raw_format",
            database_location="s3://5a-datalake-prod/raw/clustering_image_model/",
            partitions=self.partition_cols,
            force_recreate=False,
        )

        mock_metastore_svc.create_new_partitions_from_df.assert_called_once_with(
            df=self.mock_df,
            database_name="datalake_clustering_image_model_raw",
            table_name=self.raw_table_name,
            partition_cols=self.partition_cols,
        )


if __name__ == "__main__":
    unittest.main()
