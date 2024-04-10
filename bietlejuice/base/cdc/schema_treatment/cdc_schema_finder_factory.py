import json
from bietlejuice.base.cdc.schema_treatment.cdc_schema_finder import CdcSchemaFinder
from bietlejuice.base.cdc.schema_treatment.postgres_cdc_schema_finder import (
    PostgresCdcSchemaFinder,
)
from bietlejuice.base.cdc.schema_treatment.mysql_cdc_schema_finder import (
    MySqlCdcSchemaFinder,
)
from bietlejuice.base.airflow.enums.database_type_enum import DatabaseTypeEnum
from bietlejuice.base.spark.base_spark import BaseDBUtils
from bietlejuice.clients.db_clients.spark_client import SparkClient
from bietlejuice.consumers.db_consumers import PostgresConsumer


class CdcSchemaFinderFactory:
    def __init__(
        self,
        incoming_bucket: str,
        source_database: str,
        source_schema: str,
        environment: str,
        start_date: str,
        end_date: str,
        dbutils_secret_key: str,
    ) -> None:
        self.incoming_bucket = incoming_bucket
        self.source_database = source_database
        self.source_schema = source_schema
        self.environment = environment
        self.start_date = start_date
        self.end_date = end_date
        self.dbutils_secret_key = dbutils_secret_key

    def get_cdc_schema_finder(self, database_type: DatabaseTypeEnum) -> CdcSchemaFinder:
        if database_type == DatabaseTypeEnum.POSTGRES:
            return self.get_postgres_cdc_schema_finder()
        if database_type == DatabaseTypeEnum.MYSQL:
            return self.get_mysql_cdc_schema_finder()
        raise ValueError(f"Database type {database_type} not supported")

    def get_postgres_cdc_schema_finder(self) -> CdcSchemaFinder:
        conn_config = self._get_conn_config()
        spark_client = SparkClient()
        consumer = PostgresConsumer(conn_config, spark_client)
        return PostgresCdcSchemaFinder(consumer)

    def get_mysql_cdc_schema_finder(self) -> CdcSchemaFinder:
        return MySqlCdcSchemaFinder(
            f"s3://{self.incoming_bucket}/{self.source_database}/{self.environment}_{self.source_schema}.data/",
            start_date=self.start_date,
            end_date=self.end_date,
            schema=self.source_schema,
        )

    def _get_conn_config(self):
        base_dbutils = BaseDBUtils()
        if base_dbutils.get_dbutils() is not None:
            global dbutils
            dbutils = base_dbutils.get_dbutils()

        conn_config_json = dbutils.secrets.get(
            scope="quintoandar", key=self.dbutils_secret_key
        )

        return json.loads(conn_config_json)
