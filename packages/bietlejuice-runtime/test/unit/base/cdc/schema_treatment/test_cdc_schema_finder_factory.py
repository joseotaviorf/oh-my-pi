from unittest import mock

import pytest

from bietlejuice.base.airflow.enums.database_type_enum import DatabaseTypeEnum
from bietlejuice.base.cdc.schema_treatment.cdc_schema_finder_factory import (
    CdcSchemaFinderFactory,
)
from bietlejuice.base.cdc.schema_treatment.mysql_cdc_schema_finder import (
    MySqlCdcSchemaFinder,
)
from bietlejuice.base.cdc.schema_treatment.postgres_cdc_schema_finder import (
    PostgresCdcSchemaFinder,
)


class TestCdcSchemaFinderFactory:
    @pytest.fixture
    def postgres_consumer(self):
        with mock.patch(
            "bietlejuice.base.cdc.schema_treatment.cdc_schema_finder_factory.PostgresConsumer"
        ) as mock_consumer:
            yield mock_consumer

    @pytest.fixture
    def mysql_consumer(self):
        with mock.patch(
            "bietlejuice.base.cdc.schema_treatment.cdc_schema_finder_factory.MySqlConsumer"
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
        factory = CdcSchemaFinderFactory("dbutils_secret_key")

        cdc_schema_finder = factory.get_cdc_schema_finder(DatabaseTypeEnum.POSTGRES)

        assert isinstance(cdc_schema_finder, PostgresCdcSchemaFinder)
        assert cdc_schema_finder.postgres_consumer == postgres_consumer.return_value

    def test_get_cdc_schema_finder_should_return_mysql_cdc_schema_finder_if_given_enum(
        self, mysql_consumer
    ):
        factory = CdcSchemaFinderFactory("dbutils_secret_key")

        cdc_schema_finder = factory.get_cdc_schema_finder(DatabaseTypeEnum.MYSQL)

        assert isinstance(cdc_schema_finder, MySqlCdcSchemaFinder)
        assert cdc_schema_finder.mysql_consumer == mysql_consumer.return_value
        assert cdc_schema_finder.use_driver_jdbc is False

    @pytest.mark.parametrize(
        "secret_key", ["ZONAPROP_DB", "IMOVELWEB_DB", "REALESTATE_DB"]
    )
    def test_mysql_schema_finder_uses_driver_jdbc_for_navent_secrets(
        self, mysql_consumer, secret_key
    ):
        factory = CdcSchemaFinderFactory(secret_key)

        cdc_schema_finder = factory.get_cdc_schema_finder(DatabaseTypeEnum.MYSQL)

        assert cdc_schema_finder.use_driver_jdbc is True

    def test_mysql_schema_finder_keeps_spark_jdbc_for_other_secrets(
        self, mysql_consumer
    ):
        factory = CdcSchemaFinderFactory("EBDB_DB")

        cdc_schema_finder = factory.get_cdc_schema_finder(DatabaseTypeEnum.MYSQL)

        assert cdc_schema_finder.use_driver_jdbc is False
