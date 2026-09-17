import pytest

from bietlejuice.base.db.datalake_metastore_mapping import (
    CONSUMPTION_SCHEMAS,
    SCHEMAS_WITHOUT_DATALAKE_PREFIX,
    DatalakeMetastoreMapping,
)
from bietlejuice.base.pipeline.layer_enum import LayerEnum

_GOVERNED_SCHEMAS = tuple(sorted(SCHEMAS_WITHOUT_DATALAKE_PREFIX))
_CONSUMPTION_SCHEMAS = tuple(sorted(CONSUMPTION_SCHEMAS))


class TestSchemaRegistryConsistency:
    def test_consumption_schemas_are_subset_of_prefix_free_naming(self):
        # Every consumption domain must remain prefix-free (no silent drift).
        assert CONSUMPTION_SCHEMAS <= SCHEMAS_WITHOUT_DATALAKE_PREFIX
        assert CONSUMPTION_SCHEMAS is not SCHEMAS_WITHOUT_DATALAKE_PREFIX


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
            "db_core_name": "_my_src_",
            "db_core_path": "s3a://bucket-forno/core/_my_src_/",
            "db_raw_name": "datalake__my_src__raw",
            "db_raw_path": "s3a://bucket-forno/raw/_my_src_/",
            "db_enrich_name": "datalake__my_src_",
            "db_enrich_path": "s3a://bucket-forno/enrich/_my_src_/",
            "db_consumption_name": "_my_src_",
            "db_consumption_path": "s3a://bucket-forno/consumption/_my_src_/",
            "db_transactional_name": "datalake__my_src__transactional",
            "db_transactional_path": "s3a://bucket-forno/transactional/_my_src_/",
            "db_wonka_name": "wonka",
            "db_wonka_path": "s3a://bucket-forno/wonka/historical/_my_src_/",
            "db_ingestion_name": "datalake__my_src__transactional",
            "db_ingestion_path": "s3a://bucket-forno/transactional/_my_src_/",
            "db_transformation_clean_name": "transformation__my_src__clean",
            "db_transformation_clean_path": "s3a://bucket-forno/transformation/_my_src_/clean/",
            "db_transformation_curated_name": "transformation__my_src__curated",
            "db_transformation_curated_path": "s3a://bucket-forno/transformation/_my_src_/curated/",
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
            "db_core_name": "_my_src_",
            "db_core_path": "s3a://5a-datalake-prod/core/_my_src_/",
            "db_raw_name": "datalake__my_src__raw",
            "db_raw_path": "s3a://5a-datalake-prod/raw/_my_src_/",
            "db_enrich_name": "datalake__my_src_",
            "db_enrich_path": "s3a://5a-datalake-prod/enrich/_my_src_/",
            "db_consumption_name": "_my_src_",
            "db_consumption_path": "s3a://5a-datalake-prod/consumption/_my_src_/",
            "db_transactional_name": "datalake__my_src__transactional",
            "db_transactional_path": "s3a://5a-datalake-prod/transactional/_my_src_/",
            "db_wonka_name": "wonka",
            "db_wonka_path": "s3a://5a-datalake-prod/wonka/historical/_my_src_/",
            "db_ingestion_name": "datalake__my_src__transactional",
            "db_ingestion_path": "s3a://5a-datalake-prod/transactional/_my_src_/",
            "db_transformation_clean_name": "transformation__my_src__clean",
            "db_transformation_clean_path": "s3a://5a-datalake-prod/transformation/_my_src_/clean/",
            "db_transformation_curated_name": "transformation__my_src__curated",
            "db_transformation_curated_path": "s3a://5a-datalake-prod/transformation/_my_src_/curated/",
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

    def test_get_schema_from_database_for_transactional(self):
        # arrange
        database = "datalake_my_schema_transactional"

        # act
        schema = DatalakeMetastoreMapping.get_schema_from_database(database)

        # assert
        assert schema == "my_schema"

    def test_get_schema_from_database_for_raw(self):
        # arrange
        database = "datalake_my_schema_raw"

        # act
        schema = DatalakeMetastoreMapping.get_schema_from_database(database)

        # assert
        assert schema == "my_schema"

    def test_get_schema_from_database_for_clean(self):
        # arrange
        database = "datalake_my_schema_clean"

        # act
        schema = DatalakeMetastoreMapping.get_schema_from_database(database)

        # assert
        assert schema == "my_schema"

    def test_get_schema_from_database_for_transformation(self):
        # arrange
        database = "transformation_my_schema_clean"

        # act
        schema = DatalakeMetastoreMapping.get_schema_from_database(database)

        # assert
        assert schema == "my_schema"

    @pytest.mark.parametrize("grade", ("clean", "curated"))
    def test_transformation_database_name_round_trips_to_the_schema(self, grade):
        """The dependency-file generator derives task names by inverting the
        database name; a None schema here silently corrupts dependencies.yaml."""
        # arrange
        source = "my_schema"
        mapping = DatalakeMetastoreMapping(source, "a-bucket")

        # act
        database = mapping.get_full_database_name(
            LayerEnum.TRANSFORMATION, transformation_grade=grade
        )

        # assert
        assert database == f"transformation_my_schema_{grade}"
        assert DatalakeMetastoreMapping.get_schema_from_database(database) == source

    def test_transformation_requires_grade(self):
        mapping = DatalakeMetastoreMapping("my_schema", "a-bucket")
        with pytest.raises(ValueError, match="transformation_grade"):
            mapping.get_full_database_name(LayerEnum.TRANSFORMATION)

    def test_get_schema_from_database_for_core(self):
        # arrange
        database = "core_my_schema"

        # act
        schema = DatalakeMetastoreMapping.get_schema_from_database(database)

        # assert
        assert schema == "my_schema"

    def test_get_schema_from_database_for_enrich(self):
        # arrange
        database = "datalake_my_schema"

        # act
        schema = DatalakeMetastoreMapping.get_schema_from_database(database)

        # assert
        assert schema == "my_schema"

    def test_get_schema_from_database_for_other(self):
        # arrange
        database = "other"

        # act
        schema = DatalakeMetastoreMapping.get_schema_from_database(database)

        # assert
        assert schema is None

    @pytest.mark.parametrize("source", _GOVERNED_SCHEMAS)
    def test_enrich_governed_schema_drops_datalake_prefix(self, source):
        # arrange: a schema following the new naming convention (no datalake_ prefix)
        datalake_bucket = "bucket-forno"

        # act
        db_name = DatalakeMetastoreMapping(
            source, datalake_bucket
        ).get_full_database_name(LayerEnum.ENRICH)

        # assert
        assert db_name == source

    @pytest.mark.parametrize("source", _GOVERNED_SCHEMAS)
    def test_governed_schema_only_affects_name_not_path(self, source):
        # arrange
        datalake_bucket = "bucket-forno"

        # act
        db_path = DatalakeMetastoreMapping(
            source, datalake_bucket
        ).get_full_database_path(LayerEnum.ENRICH)

        # assert: the S3 path never carried the datalake_ prefix, so it is unchanged
        assert db_path == f"s3a://bucket-forno/enrich/{source}/"

    def test_enrich_non_governed_schema_keeps_datalake_prefix(self):
        # arrange: a regular schema is untouched
        source = "some_domain"
        datalake_bucket = "bucket-forno"

        # act
        db_name = DatalakeMetastoreMapping(
            source, datalake_bucket
        ).get_full_database_name(LayerEnum.ENRICH)

        # assert
        assert db_name == "datalake_some_domain"

    @pytest.mark.parametrize("source", _GOVERNED_SCHEMAS)
    def test_get_schema_from_database_for_governed_enrich(self, source):
        # arrange: prefixless governed name (enrich)
        database = source

        # act
        schema = DatalakeMetastoreMapping.get_schema_from_database(database)

        # assert
        assert schema == source

    @pytest.mark.parametrize("source", _GOVERNED_SCHEMAS)
    def test_get_schema_from_database_for_governed_with_layer_suffix(self, source):
        # arrange: prefixless governed name with a layer suffix
        database = f"{source}_clean"

        # act
        schema = DatalakeMetastoreMapping.get_schema_from_database(database)

        # assert
        assert schema == source

    @pytest.mark.parametrize("source", _GOVERNED_SCHEMAS)
    def test_get_schema_from_database_roundtrips_governed_name(self, source):
        # arrange: the reverse must invert get_full_database_name for governed schemas
        db_name = DatalakeMetastoreMapping(
            source, "bucket-forno"
        ).get_full_database_name(LayerEnum.ENRICH)

        # act
        schema = DatalakeMetastoreMapping.get_schema_from_database(db_name)

        # assert
        assert schema == source

    def test_get_schema_from_database_non_governed_prefixless_still_none(self):
        # arrange: a prefixless, non-governed name is still unrecoverable (unchanged behavior)
        database = "random_thing"

        # act
        schema = DatalakeMetastoreMapping.get_schema_from_database(database)

        # assert
        assert schema is None

    @pytest.mark.parametrize("source", _CONSUMPTION_SCHEMAS)
    def test_consumption_schema_is_prefix_free(self, source):
        datalake_bucket = "bucket-forno"

        db_name = DatalakeMetastoreMapping(
            source, datalake_bucket
        ).get_full_database_name(LayerEnum.CONSUMPTION)

        assert db_name == source
        assert not db_name.startswith("datalake_")
        assert not db_name.startswith("consumption_")

    def test_consumption_new_domain_is_prefix_free(self):
        source = "new_domain"
        datalake_bucket = "bucket-forno"

        db_name = DatalakeMetastoreMapping(
            source, datalake_bucket
        ).get_full_database_name(LayerEnum.CONSUMPTION)

        assert db_name == "new_domain"
        assert not db_name.startswith("datalake_")
        assert not db_name.startswith("consumption_")

    @pytest.mark.parametrize("source", _CONSUMPTION_SCHEMAS)
    def test_consumption_path_uses_consumption_storage_root(self, source):
        datalake_bucket = "bucket-forno"

        db_path = DatalakeMetastoreMapping(
            source, datalake_bucket
        ).get_full_database_path(LayerEnum.CONSUMPTION)

        assert db_path == f"s3a://bucket-forno/consumption/{source}/"

    @pytest.mark.parametrize("source", _CONSUMPTION_SCHEMAS)
    def test_consumption_name_roundtrips_via_get_schema_from_database(self, source):
        db_name = DatalakeMetastoreMapping(
            source, "bucket-forno"
        ).get_full_database_name(LayerEnum.CONSUMPTION)

        assert DatalakeMetastoreMapping.get_schema_from_database(db_name) == source

    @pytest.mark.parametrize("source", _CONSUMPTION_SCHEMAS)
    def test_enrich_and_consumption_share_physical_name_for_registered_domains(
        self, source
    ):
        # Documents the P1 ambiguity: both layers resolve to the same metastore DB
        # for registered domains; classifier therefore prefers consumption.
        enrich_name = DatalakeMetastoreMapping(
            source, "bucket-forno"
        ).get_full_database_name(LayerEnum.ENRICH)
        consumption_name = DatalakeMetastoreMapping(
            source, "bucket-forno"
        ).get_full_database_name(LayerEnum.CONSUMPTION)
        assert enrich_name == consumption_name == source
