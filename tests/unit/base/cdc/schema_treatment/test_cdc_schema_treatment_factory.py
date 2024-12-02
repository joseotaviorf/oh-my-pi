import pytest
from unittest import mock

from bietlejuice.base.airflow.enums.database_type_enum import DatabaseTypeEnum
from bietlejuice.base.cdc.schema_treatment.cdc_schema_treatment_factory import (
    CdcSchemaTreatmentFactory,
)
from bietlejuice.base.cdc.schema_treatment.mysql_cdc_schema_treatment import (
    MySqlCdcSchemaTreatment,
)
from bietlejuice.base.cdc.schema_treatment.postgres_cdc_schema_treatment import (
    PostgresCdcSchemaTreatment,
)


class TestCdcSchemaTreatmentFactory:
    @pytest.fixture
    def postgres_cdc_schema_finder(self):
        with mock.patch(
            "bietlejuice.base.cdc.schema_treatment.postgres_cdc_schema_finder.PostgresCdcSchemaFinder"
        ) as mock_postgres_cdc_schema_finder:
            yield mock_postgres_cdc_schema_finder

    @pytest.fixture
    def mysql_cdc_schema_finder(self):
        with mock.patch(
            "bietlejuice.base.cdc.schema_treatment.mysql_cdc_schema_finder.MySqlCdcSchemaFinder"
        ) as mock_mysql_cdc_schema_finder:
            yield mock_mysql_cdc_schema_finder

    def test_cdc_schema_treatment_factory_should_return_postgres_schema_treatment(
        self, postgres_cdc_schema_finder
    ):
        factory = CdcSchemaTreatmentFactory(
            schema_finder=postgres_cdc_schema_finder,
            datalake_table_schema="datalake_layer_test.table_name",
            transactional_datatype_overrides={},
        )

        cdc_schema_treatment = factory.get_cdc_schema_treatment(
            DatabaseTypeEnum.POSTGRES
        )

        assert isinstance(cdc_schema_treatment, PostgresCdcSchemaTreatment)
        assert cdc_schema_treatment.schema_finder == postgres_cdc_schema_finder

    def test_cdc_schema_treatment_factory_should_return_mysql_schema_treatment(
        self, mysql_cdc_schema_finder
    ):
        factory = CdcSchemaTreatmentFactory(
            schema_finder=mysql_cdc_schema_finder,
            datalake_table_schema="datalake_layer_test.table_name",
            transactional_datatype_overrides={},
        )

        cdc_schema_treatment = factory.get_cdc_schema_treatment(DatabaseTypeEnum.MYSQL)

        assert isinstance(cdc_schema_treatment, MySqlCdcSchemaTreatment)
        assert cdc_schema_treatment.schema_finder == mysql_cdc_schema_finder

    def test_cdc_schema_treatment_database_unsupported(self, mysql_cdc_schema_finder):
        factory = CdcSchemaTreatmentFactory(
            schema_finder=mysql_cdc_schema_finder,
            datalake_table_schema="datalake_layer_test.table_name",
            transactional_datatype_overrides={},
        )

        with pytest.raises(ValueError):
            factory.get_cdc_schema_treatment("unsupported_database")
