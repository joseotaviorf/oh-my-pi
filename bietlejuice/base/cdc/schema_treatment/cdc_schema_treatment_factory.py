from bietlejuice.base.airflow.enums.database_type_enum import DatabaseTypeEnum
from bietlejuice.base.cdc.schema_treatment.cdc_schema_finder import CdcSchemaFinder
from bietlejuice.base.cdc.schema_treatment.cdc_schema_treatment import (
    CdcSchemaTreatment,
)
from bietlejuice.base.cdc.schema_treatment.mysql_cdc_schema_treatment import (
    MySqlCdcSchemaTreatment,
)
from bietlejuice.base.cdc.schema_treatment.postgres_cdc_schema_treatment import (
    PostgresCdcSchemaTreatment,
)


class CdcSchemaTreatmentFactory:
    def __init__(
        self,
        schema_finder: CdcSchemaFinder,
        datalake_table_schema: str,
        transactional_datatype_overrides: dict,
    ) -> None:
        self.schema_finder = schema_finder
        self.datalake_table_schema = datalake_table_schema
        self.transactional_datatype_overrides = transactional_datatype_overrides

    def get_cdc_schema_treatment(
        self, database_type: DatabaseTypeEnum
    ) -> CdcSchemaTreatment:
        if database_type == DatabaseTypeEnum.POSTGRES:
            return self.get_postgres_cdc_schema_treatment()
        if database_type == DatabaseTypeEnum.MYSQL:
            return self.get_mysql_cdc_schema_treatment()
        raise ValueError(f"Database type {database_type} not supported")

    def get_postgres_cdc_schema_treatment(self) -> CdcSchemaTreatment:
        return PostgresCdcSchemaTreatment(
            self.schema_finder,
            self.datalake_table_schema,
            self.transactional_datatype_overrides,
        )

    def get_mysql_cdc_schema_treatment(self) -> CdcSchemaTreatment:
        return MySqlCdcSchemaTreatment(
            self.schema_finder,
            self.datalake_table_schema,
            self.transactional_datatype_overrides,
        )
