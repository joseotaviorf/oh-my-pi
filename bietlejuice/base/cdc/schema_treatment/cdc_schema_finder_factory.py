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
from bietlejuice.consumers.db_consumers.postgres_consumer import PostgresConsumer
from bietlejuice.consumers.db_consumers.mysql_consumer import MySqlConsumer


class CdcSchemaFinderFactory:
    def __init__(self, dbutils_secret_key: str) -> None:
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
        conn_config = self._get_conn_config()
        spark_client = SparkClient()
        mysql_consumer = MySqlConsumer(conn_config, spark_client)
        return MySqlCdcSchemaFinder(mysql_consumer)

    def _get_conn_config(self):
        base_dbutils = BaseDBUtils()
        dbutils = base_dbutils.get_dbutils()
        conn_config_json = dbutils.secrets.get(
            scope="quintoandar", key=self.dbutils_secret_key
        )

        return json.loads(conn_config_json)
