from collections import OrderedDict
from unittest import mock
from unittest.mock import Mock

import pytest
from pyspark.sql.types import StringType, StructField, StructType

from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.metastore_services.metastore_service import MetastoreService


class TestSparkMetastoreService:
    @pytest.fixture(autouse=True)
    def unity_catalog_helper(self):
        with mock.patch(
            "bietlejuice.base.spark.unity_catalog_helper.UnityCatalogHelper"
        ) as unity_catalog_helper:
            yield unity_catalog_helper

    def test_client(self, spark_metastore_service):
        # arrange
        mocked_client = Mock()
        spark_metastore_service._client = mocked_client

        # act
        returned_value = spark_metastore_service.client

        # assert
        assert returned_value == mocked_client

    @mock.patch.object(
        SparkMetastoreService, "_get_partition_keys_from_table_description"
    )
    @mock.patch.object(MetastoreService, "get_table_description")
    def test_get_table_schema_not_ignoring_partition_keys(
        self,
        mocked_get_table_description,
        mocked__get_partition_keys_from_table_description,
        sql_context,
        spark_metastore_service,
    ):
        # arrange
        database_name = "cool_db"
        table_name = "cool_table"
        mocked_result_df = sql_context.createDataFrame(
            [
                ("c1", "int", "bar"),
                ("c2", "string", "bar"),
                ("c3", "string", "bar"),
                ("c4", "string", "bar"),
            ],
            ["col_name", "data_type", "foo"],
        )

        mocked_get_table_description.return_value = mocked_result_df

        # act
        returned_value = spark_metastore_service.get_table_schema(
            database_name, table_name
        )

        # assert
        assert returned_value == OrderedDict(
            [("c1", "int"), ("c2", "string"), ("c3", "string"), ("c4", "string")]
        )
        mocked__get_partition_keys_from_table_description.assert_not_called()
        mocked_get_table_description.assert_called_once_with(database_name, table_name)

    @pytest.mark.parametrize(
        "mocked_result_df_data, mocked_result_df_schema, mocked_partition_keys, expected_columns",
        [
            (  # table with partitions
                [
                    ("c1", "int", "bar"),
                    ("c2", "string", "bar"),
                    ("c3", "string", "bar"),
                    ("p1", "string", "bar"),
                    ("p2", "string", "bar"),
                ],
                ["col_name", "data_type", "foo"],
                {"p1": "string", "p2": "string"},
                OrderedDict([("c1", "int"), ("c2", "string"), ("c3", "string")]),
            ),
            (  # table without partitions
                [
                    ("c1", "int", "bar"),
                    ("c2", "string", "bar"),
                    ("c3", "string", "bar"),
                    ("c4", "string", "bar"),
                    ("c5", "string", "bar"),
                ],
                ["col_name", "data_type", "foo"],
                {},
                OrderedDict(
                    [
                        ("c1", "int"),
                        ("c2", "string"),
                        ("c3", "string"),
                        ("c4", "string"),
                        ("c5", "string"),
                    ]
                ),
            ),
        ],
    )
    @mock.patch.object(
        SparkMetastoreService, "_get_partition_keys_from_table_description"
    )
    @mock.patch.object(MetastoreService, "get_table_description")
    def test_get_table_schema_ignoring_partition_keys(
        self,
        mocked_get_table_description,
        mocked__get_partition_keys_from_table_description,
        mocked_result_df_data,
        mocked_result_df_schema,
        mocked_partition_keys,
        expected_columns,
        sql_context,
        spark_metastore_service,
    ):
        # arrange
        database_name = "cool_db"
        table_name = "cool_table"
        mocked_result_df = sql_context.createDataFrame(
            mocked_result_df_data, mocked_result_df_schema
        )

        mocked__get_partition_keys_from_table_description.return_value = (
            mocked_partition_keys
        )

        mocked_get_table_description.return_value = mocked_result_df

        # act
        returned_value = spark_metastore_service.get_table_schema(
            database_name, table_name, ignore_partition_keys=True
        )

        # assert
        assert returned_value == expected_columns
        mocked__get_partition_keys_from_table_description.assert_called_once_with(
            mocked_result_df
        )
        mocked_get_table_description.assert_called_once_with(database_name, table_name)

    @pytest.mark.parametrize(
        "mocked_result_df_data, mocked_result_df_schema,expected_return",
        [
            (
                [
                    ("c1", "int", "bar"),
                    ("c2", "string", "bar"),
                    ("c3", "string", "bar"),
                    ("# Partition information", "", ""),
                    ("# col_name", "", ""),  # simulates the describe command in hive
                    ("p1", "string", "bar"),
                    ("p2", "string", "bar"),
                ],
                ["col_name", "data_type", "foo"],
                OrderedDict([("p1", "string"), ("p2", "string")]),
            ),
            (
                [],
                StructType(  # defining schema because of empty data set
                    [
                        StructField("col_name", StringType(), True),
                        StructField("data_type", StringType(), True),
                        StructField("foo", StringType(), True),
                    ]
                ),
                OrderedDict([]),
            ),
        ],
    )
    def test__get_partition_keys_from_table_description(
        self,
        mocked_result_df_data,
        mocked_result_df_schema,
        expected_return,
        sql_context,
        spark_metastore_service,
    ):
        # arrange
        mocked_result_df = sql_context.createDataFrame(
            mocked_result_df_data, mocked_result_df_schema, verifySchema=False
        )

        # act
        returned_value = (
            spark_metastore_service._get_partition_keys_from_table_description(
                mocked_result_df
            )
        )

        # assert
        assert returned_value == expected_return

    @mock.patch.object(MetastoreService, "get_table_description")
    @mock.patch.object(
        SparkMetastoreService, "_get_partition_keys_from_table_description"
    )
    def test_get_table_partition_keys(
        self,
        mocked__get_partition_keys_from_table_description,
        mocked_get_table_description,
        sql_context,
        spark_metastore_service,
    ):
        # arrange
        database_name = "database_name"
        table_name = "table_name"
        mocked_result_df = sql_context.createDataFrame(
            [
                ("c1", "int", "bar"),
                ("c2", "string", "bar"),
                ("c3", "string", "bar"),
                ("# Partition information", "", ""),
                ("# col_name", "", ""),  # simulates the describe command in hive
                ("p1", "string", "bar"),
                ("p2", "string", "bar"),
            ],
            ["col_name", "data_type", "foo"],
            verifySchema=False,
        )
        mocked_get_table_description.return_value = mocked_result_df
        partition_keys = OrderedDict([("p1", "string"), ("p2", "string")])
        mocked__get_partition_keys_from_table_description.return_value = partition_keys
        expected_result = [("p1", "string"), ("p2", "string")]

        # act
        returned_value = spark_metastore_service.get_table_partition_keys(
            database_name, table_name
        )

        # assert
        mocked_get_table_description.assert_called_once_with(database_name, table_name)
        mocked__get_partition_keys_from_table_description.assert_called_once_with(
            mocked_result_df
        )
        assert returned_value == expected_result

    @mock.patch(
        "bietlejuice.services.metastore_services.metastore_service.MetastoreService.create_new_partitions_from_df"
    )
    def test_create_new_partitions_from_df_should_call_metastore_service(
        self,
        mocked_create_new_partitions_from_df,
        spark_metastore_service,
        unity_catalog_helper,
    ):
        # arrange
        database_name = "database_name"
        table_name = "table_name"
        partition_cols = ["year", "month", "day"]
        df = Mock()
        unity_catalog_helper.is_default_catalog_using_unity.return_value = False

        # act
        spark_metastore_service.create_new_partitions_from_df(
            database_name, table_name, df, partition_cols, 1
        )

        # assert
        mocked_create_new_partitions_from_df.assert_called_once_with(
            database_name, table_name, df, partition_cols, 1
        )

    @mock.patch(
        "bietlejuice.services.metastore_services.metastore_service.MetastoreService.create_new_partitions_from_df"
    )
    def test_create_new_partitions_from_df_should_not_call_metastore_service_if_uc_enabled(
        self,
        mocked_create_new_partitions_from_df,
        spark_metastore_service,
        unity_catalog_helper,
    ):
        # arrange
        database_name = "database_name"
        table_name = "table_name"
        partition_cols = ["year", "month", "day"]
        df = Mock()
        unity_catalog_helper.is_default_catalog_using_unity.return_value = True

        # act
        spark_metastore_service.create_new_partitions_from_df(
            database_name, table_name, df, partition_cols, 1
        )

        # assert
        mocked_create_new_partitions_from_df.assert_not_called()

    @mock.patch(
        "bietlejuice.services.metastore_services.metastore_service.MetastoreService.create_new_partitions_from_df"
    )
    def test_create_new_partitions_from_df_should_not_sync_if_uc_disabled(
        self,
        mocked_create_new_partitions_from_df,
        spark_metastore_service,
        unity_catalog_helper,
    ):
        # arrange
        database_name = "database_name"
        table_name = "table_name"
        partition_cols = ["year", "month", "day"]
        df = Mock()
        unity_catalog_helper.is_cluster_unity_catalog_enabled.return_value = False
        unity_catalog_helper.is_default_catalog_using_unity.return_value = False

        # act
        spark_metastore_service.create_new_partitions_from_df(
            database_name, table_name, df, partition_cols, 1
        )

        # assert
        unity_catalog_helper.sync_table_to_unity_catalog.assert_not_called()

    @mock.patch(
        "bietlejuice.services.metastore_services.metastore_service.MetastoreService.create_new_partitions_from_df"
    )
    def test_create_new_partitions_from_df_should_not_sync_if_uc_enabled_but_table_saved_directly_to_uc(
        self,
        mocked_create_new_partitions_from_df,
        spark_metastore_service,
        unity_catalog_helper,
    ):
        # arrange
        database_name = "database_name"
        table_name = "table_name"
        partition_cols = ["year", "month", "day"]
        df = Mock()
        unity_catalog_helper.is_cluster_unity_catalog_enabled.return_value = True
        unity_catalog_helper.is_default_catalog_using_unity.return_value = True

        # act
        spark_metastore_service.create_new_partitions_from_df(
            database_name, table_name, df, partition_cols, 1
        )

        # assert
        unity_catalog_helper.sync_table_to_unity_catalog.assert_not_called()

    @mock.patch(
        "bietlejuice.services.metastore_services.metastore_service.MetastoreService.create_new_partitions_from_df"
    )
    def test_create_new_partitions_from_df_should_not_sync_if_table_is_not_partitioned(
        self,
        mocked_create_new_partitions_from_df,
        spark_metastore_service,
        unity_catalog_helper,
    ):
        # arrange
        database_name = "database_name"
        table_name = "table_name"
        partition_cols = []
        df = Mock()
        unity_catalog_helper.is_cluster_unity_catalog_enabled.return_value = True
        unity_catalog_helper.is_default_catalog_using_unity.return_value = False

        # act
        spark_metastore_service.create_new_partitions_from_df(
            database_name, table_name, df, partition_cols, 1
        )

        # assert
        unity_catalog_helper.sync_table_to_unity_catalog.assert_not_called()

    @mock.patch(
        "bietlejuice.services.metastore_services.metastore_service.MetastoreService.create_new_partitions_from_df"
    )
    def test_create_new_partitions_from_df_should_sync_if_uc_enabled_and_table_partitioned(
        self,
        mocked_create_new_partitions_from_df,
        spark_metastore_service,
        unity_catalog_helper,
    ):
        # arrange
        database_name = "database_name"
        table_name = "table_name"
        partition_cols = ["year", "month", "day"]
        df = Mock()
        unity_catalog_helper.is_cluster_unity_catalog_enabled.return_value = True
        unity_catalog_helper.is_default_catalog_using_unity.return_value = False

        # act
        spark_metastore_service.create_new_partitions_from_df(
            database_name, table_name, df, partition_cols, 1
        )

        # assert
        unity_catalog_helper.sync_table_to_unity_catalog.assert_called_once_with(
            f"{database_name}.{table_name}"
        )


class TestMergeTableAndDataframeSchemas:
    """The union must match column names case-insensitively.

    Databricks' metastore preserves the dataframe's casing; Hive/Glue lower-cases
    it. A case-sensitive union therefore re-appends every camelCased dataframe
    column on EMR, and ``spark.sql.caseSensitive=false`` makes the resulting DDL
    illegal (``COLUMN_ALREADY_EXISTS``).
    """

    @staticmethod
    def _service(table_schema, table_name="t"):
        service = SparkMetastoreService(Mock())
        service.get_table_names = Mock(return_value=[table_name])
        service.get_table_schema = Mock(return_value=table_schema)
        return service

    @staticmethod
    def _df(*columns):
        return Mock(
            schema=StructType([StructField(name, StringType()) for name in columns])
        )

    def test_databricks_casing_matches_so_schema_is_unchanged(self):
        """The Databricks case: table casing == df casing. Must be a no-op."""
        table_schema = OrderedDict(
            [("Id", "string"), ("BusinessProcessId", "string"), ("year", "int")]
        )
        service = self._service(table_schema)

        merged = service.merge_table_and_dataframe_schemas(
            "db", "t", self._df("Id", "BusinessProcessId", "year")
        )

        # Equality is what SparkMetastoreLoader.create_merge_schema tests to
        # decide whether to drop and recreate the table.
        assert merged == table_schema

    def test_emr_lowercased_table_does_not_duplicate_camelcase_column(self):
        """The EMR case: Glue returned lower-case, the df still has PascalCase."""
        table_schema = OrderedDict(
            [("id", "string"), ("businessprocessid", "string"), ("year", "int")]
        )
        service = self._service(table_schema)

        merged = service.merge_table_and_dataframe_schemas(
            "db", "t", self._df("Id", "BusinessProcessId", "year")
        )

        assert merged == table_schema
        assert list(merged) == ["id", "businessprocessid", "year"]

    def test_genuinely_new_column_is_still_added(self):
        table_schema = OrderedDict([("id", "string")])
        service = self._service(table_schema)

        merged = service.merge_table_and_dataframe_schemas(
            "db", "t", self._df("Id", "brand_new")
        )

        assert merged == OrderedDict([("id", "string"), ("brand_new", "string")])

    def test_existing_casing_is_never_rewritten(self):
        """No key may be replaced by a differently-cased variant of itself."""
        table_schema = OrderedDict([("BusinessProcessId", "string")])
        service = self._service(table_schema)

        merged = service.merge_table_and_dataframe_schemas(
            "db", "t", self._df("businessprocessid")
        )

        assert list(merged) == ["BusinessProcessId"]

    def test_df_with_internal_case_collision_adds_only_one(self):
        """A df carrying both spellings must not produce an illegal DDL."""
        table_schema = OrderedDict([("id", "string")])
        service = self._service(table_schema)

        merged = service.merge_table_and_dataframe_schemas(
            "db", "t", self._df("userId", "userid")
        )

        assert [col.lower() for col in merged] == ["id", "userid"]
