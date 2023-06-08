from bietlejuice.base.db.reverse_metastore_mapping import ReverseMetastoreMapping


class TestReverseMetastoreMapping:
    def test_get_all_reverse_info(self):
        source = "atento"
        bucket = "5a-datalake-prod"
        mapping = ReverseMetastoreMapping(source, bucket)

        reverse_info = mapping.get_all_reverse_info()

        assert reverse_info == {
            "reverse_schema_name": "reverse_atento",
            "reverse_schema_path": "s3://5a-datalake-prod/reverse/atento/",
        }

    def test_get_schema_from_database_for_reverse(self):
        # arrange
        database = "reverse_my_schema"

        # act
        schema = ReverseMetastoreMapping.get_schema_from_database(database)

        # assert
        assert schema == "my_schema"

    def test_get_schema_from_database_for_other(self):
        # arrange
        database = "other"

        # act
        schema = ReverseMetastoreMapping.get_schema_from_database(database)

        # assert
        assert schema is None
