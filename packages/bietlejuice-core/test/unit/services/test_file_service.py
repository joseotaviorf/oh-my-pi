import pytest

from bietlejuice.services.file_service import FileService


class TestFileService:
    def test_get_table_info_from_path_should_raise_when_too_few_levels(self):
        path = "classified_leads/metadata/clean"
        with pytest.raises(ValueError):
            FileService.get_table_info_from_path(path)

    def test_get_table_info_from_path_should_raise_when_too_many_levels(self):
        path = "level1/level2/level3/level4/level5/level6/level7"
        with pytest.raises(ValueError):
            FileService.get_table_info_from_path(path)

    def test_get_table_info_from_path_with_simple_metadata_path(self):
        path = "ebdb/metadata/clean/access_type_aud.yml"
        expected_source = "ebdb"
        expected_layer = "clean"
        expected_context = "ebdb"
        expected_dag = "bietlejuice.ebdb"
        expected_ingestion_type = "full"
        expected_table = "access_type_aud"

        assert FileService.get_table_info_from_path(path) == (
            expected_source,
            expected_layer,
            expected_context,
            expected_dag,
            expected_ingestion_type,
            expected_table,
        )

    def test_get_table_info_from_path_with_context_after_dot(self):
        path = "dw_datamarts_spark/queries/dw/fintech/doubtful_debtors_provision.sql"
        expected_source = "dw_datamarts_spark"
        expected_layer = "dw"
        expected_context = "fintech"
        expected_dag = "bietlejuice.dw_datamarts_spark.fintech"
        expected_ingestion_type = "full"
        expected_table = "doubtful_debtors_provision"

        assert FileService.get_table_info_from_path(path) == (
            expected_source,
            expected_layer,
            expected_context,
            expected_dag,
            expected_ingestion_type,
            expected_table,
        )

    def test_get_table_info_from_path_with_incremental_ingestion_type(self):
        path = "jira/queries/clean/incremental/issues.sql"
        expected_source = "jira"
        expected_layer = "clean"
        expected_context = "jira"
        expected_dag = "bietlejuice.jira"
        expected_ingestion_type = "incremental"
        expected_table = "issues"

        assert FileService.get_table_info_from_path(path) == (
            expected_source,
            expected_layer,
            expected_context,
            expected_dag,
            expected_ingestion_type,
            expected_table,
        )

    def test_get_table_info_from_path_with_crawlers_schema(self):
        path = "crawlers/queries/clean/listings/loft/loft.sql"
        expected_source = "crawlers"
        expected_layer = "clean"
        expected_context = "listings"
        expected_dag = "bietlejuice.listings.loft"
        expected_ingestion_type = "full"
        expected_table = "loft"

        assert FileService.get_table_info_from_path(path) == (
            expected_source,
            expected_layer,
            expected_context,
            expected_dag,
            expected_ingestion_type,
            expected_table,
        )

    def test_temporary_gsheets_by_context_corner_case(self):
        path = "gsheets_by_context/queries/clean/growth/tv_ads.sql"
        expected_source = "gsheets_by_context"
        expected_layer = "clean"
        expected_context = "growth"
        expected_dag = "bietlejuice.gsheets.growth"
        expected_ingestion_type = "full"
        expected_table = "tv_ads"

        assert FileService.get_table_info_from_path(path) == (
            expected_source,
            expected_layer,
            expected_context,
            expected_dag,
            expected_ingestion_type,
            expected_table,
        )
