from bietlejuice.base.airflow.enums.database_type_enum import DatabaseTypeEnum
from bietlejuice.base.cdc.schema_treatment.cdc_schema_finder_factory import (
    CdcSchemaFinderFactory,
)
from bietlejuice.base.cdc.schema_treatment.postgres_cdc_schema_finder import (
    PostgresCdcSchemaFinder,
)
from bietlejuice.base.cdc.schema_treatment.mysql_cdc_schema_finder import (
    MySqlCdcSchemaFinder,
)
from unittest import mock
import pytest


class TestCdcSchemaFinderFactory:
    @pytest.fixture
    def postgres_consumer(self):
        with mock.patch(
            "bietlejuice.base.cdc.schema_treatment.cdc_schema_finder_factory.PostgresConsumer"
        ) as mock_consumer:
            yield mock_consumer

    @pytest.fixture(autouse=True)
    def base_dbutils(self):
        with mock.patch(
            "bietlejuice.base.cdc.schema_treatment.cdc_schema_finder_factory.BaseDBUtils"
        ) as mock_base_dbutils:
            secrets = mock.MagicMock()
            secrets.get.return_value = '{"key": "value"}'
            dbutils = mock.MagicMock()
            dbutils.secrets = secrets
            mock_base_dbutils.return_value.get_dbutils.return_value = dbutils
            yield mock_base_dbutils

    @pytest.fixture(autouse=True)
    def spark_client(self):
        with mock.patch(
            "bietlejuice.base.cdc.schema_treatment.cdc_schema_finder_factory.SparkClient"
        ) as mock_client:
            yield mock_client

    def test_get_cdc_schema_finder_should_return_postgres_cdc_schema_finder_if_given_enum(
        self, postgres_consumer
    ):
        factory = CdcSchemaFinderFactory(
            "incoming_bucket",
            "source_database",
            "source_schema",
            "environment",
            "start_date",
            "end_date",
            "dbutils_secret_key",
        )

        cdc_schema_finder = factory.get_cdc_schema_finder(DatabaseTypeEnum.POSTGRES)

        assert isinstance(cdc_schema_finder, PostgresCdcSchemaFinder)
        assert cdc_schema_finder.postgres_consumer == postgres_consumer.return_value

    def test_get_cdc_schema_finder_should_return_mysql_cdc_schema_finder_if_given_enum(
        self,
    ):
        factory = CdcSchemaFinderFactory(
            "incoming_bucket",
            "source_database",
            "source_schema",
            "environment",
            "start_date",
            "end_date",
            "dbutils_secret_key",
        )

        cdc_schema_finder = factory.get_cdc_schema_finder(DatabaseTypeEnum.MYSQL)

        assert isinstance(cdc_schema_finder, MySqlCdcSchemaFinder)
        assert (
            cdc_schema_finder.schema_changes_path
            == "s3://incoming_bucket/source_database/environment_source_schema.data/"
        )
        assert cdc_schema_finder.schema == "source_schema"
        assert cdc_schema_finder.start_date == "start_date"
        assert cdc_schema_finder.end_date == "end_date"
