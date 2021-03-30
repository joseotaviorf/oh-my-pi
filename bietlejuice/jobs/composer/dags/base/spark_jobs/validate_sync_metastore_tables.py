"""
    Validates the synchronization between in-house metastore and Databricks metastore.

    It will validate the table schema, partition keys, partition values count and table content count.
    This job is temporary and will be removed after the sync implementation is finished for all tables.
"""
import json
import logging
from argparse import ArgumentParser
import re

import requests
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatabaseEnum
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreMapping
from bietlejuice.jobs.composer.base.db.dw_metastore_mapping import DwMetastoreMapping
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.clients.db_clients import SparkClient, TrinoClient
from bietlejuice.jobs.composer.consumers.db_consumers.databricks_consumer import (
    DatabricksConsumer,
)
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

JOB_NAME = "validate_sync_metastore_tables"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


class MetastoreSyncValidation:
    SPARK_TO_TRINO_COLUMN_TYPE = {
        "string": "varchar",
        "int": "integer",
        "timestamp": "timestamp(3)",
    }

    def __init__(self, database_name, table_name, trino_conn_config) -> None:
        """
        Constructor.

        :param database_name: target database name
        :param table_name: target table that will be validated
        :param trino_conn_config: trino server configs
        :param slack_dae_webhook: webhook to post in DAE squad channel
        """
        self.database_name = database_name
        self.table_name = table_name
        self.trino_client = TrinoClient(
            trino_conn_config["host"],
            trino_conn_config["port"],
            trino_conn_config["user"],
        )

    def validate_table(self):
        if (
            self.validate_schema_and_partition_keys()
            and self.validate_partition_values_count()
            and self.validate_content()
        ):
            logger.info(
                f"m={JOB_NAME}, database={self.database_name}, table={self.table_name}, "
                f"msg=Table synchronization validation succeeded."
            )

    def validate_schema_and_partition_keys(self):
        """
        Gets and compares the table schema in Spark and In-house metastores.
         The partition keys are included in the schema comparison.

        :rtype: bool
        """
        spark_metastore_service = SparkMetastoreService(SparkClient())
        spark_ms_table_columns = spark_metastore_service.get_table_schema(
            self.database_name, self.table_name
        )
        self._validate_empty_table_schema(spark_ms_table_columns)

        trino_table_schema = self.trino_client.get_records(
            query=f"DESCRIBE {self.database_name}.{self.table_name}"
        )
        self._validate_empty_table_schema(trino_table_schema)
        trino_table_schema = self._parse_trino_schema(trino_table_schema)

        if not self._validate_table_schema_match(
            spark_ms_table_columns, trino_table_schema
        ):
            msg = (
                f"database={self.database_name}, table={self.table_name}"
                "\n\nMessage=The schema of the table in In-house Hive and Spark metastores are diverging."
            )
            notify_error_in_slack(msg)
            return False

        logger.info(
            f"m={JOB_NAME}, database={self.database_name}, table={self.table_name}, "
            "msg=Table schemas and partition keys match."
        )
        return True

    def _validate_empty_table_schema(self, table_schema):
        if not table_schema:
            raise AssertionError(
                f"m={JOB_NAME}, database={self.database_name}, table={self.table_name}, "
                "msg=The tables have an empty schema in the metastores."
            )

    @staticmethod
    def _parse_trino_schema(trino_table_schema):
        """
        Put the trino returned schema in a dict structure with the column
         name as the key and the type as the value.

        :param trino_table_schema: each column properties [name, type, comment]
        :type trino_table_schema: List[List[str, str, str]]
        :rtype: dict[str:str]
        """
        COLUMN_NAME = 0
        COLUMN_TYPE = 1

        columns = {}
        for column in trino_table_schema:
            columns[column[COLUMN_NAME]] = column[COLUMN_TYPE]

        return columns

    def _compare_tables_schema_length(self, spark_ms_table_columns, trino_table_schema):
        """
        Checks if tables have the same columns number

        :param spark_ms_table_columns: the table columns in spark metastore
        :type spark_ms_table_columns: collections.OrderedDict[(str, str)]
        :param trino_table_schema: the table columns in in-house metastore
        :type trino_table_schema: dict[str:str]
        :rtype: bool
        """
        if len(spark_ms_table_columns) != len(trino_table_schema):
            logger.error(
                f"m={JOB_NAME}, database={self.database_name}, table={self.table_name}, "
                f"spark_col_number={len(spark_ms_table_columns)} trino_col_numer={len(trino_table_schema)},"
                " msg=The tables have different column count."
            )
            return False

        return True

    def _compare_tables_schema_columns(
        self, spark_ms_table_columns, trino_table_schema
    ):
        """
        Checks if each spark table column is present in the in-house metastore
         and if the column type is the same, to validate the metastores
         synchronization.

        :param spark_ms_table_columns: the table columns in spark metastore
        :type spark_ms_table_columns: collections.OrderedDict[(str, str)]
        :param trino_table_schema: the table columns in in-house metastore
        :type trino_table_schema: dict[str:str]
        :rtype: bool
        """
        for col_name, col_type in spark_ms_table_columns.items():
            if (col_name not in trino_table_schema.keys()) or (
                trino_table_schema[col_name].replace(" ", "")
                != self._get_spark_to_trino_col_mapping(col_type).replace(" ", "")
            ):
                logger.error(
                    f"m={JOB_NAME}, database={self.database_name}, table={self.table_name}, "
                    f"column={col_name}, msg=The column diverges in both Metastore tables."
                )
                return False
        return True

    def _get_base_col_mapping(self, col_type):
        """
        Fetches the spark to hive column type mapping.

        :param col_type: str
        :return: the column if it is the same in both metastores, or the
         mapped type if they are different
        """
        if col_type in self.SPARK_TO_TRINO_COLUMN_TYPE.keys():
            return self.SPARK_TO_TRINO_COLUMN_TYPE[col_type]

        return col_type

    def _get_spark_to_trino_col_mapping(self, col_type):
        """
        The columns in Hive are created with different types from Spark.
        It fetches the column provided, identify it is a struct, such as
        map/array and apply the respective mapping.

        :param col_type: str
        :return: the column if it is the same in both metastores, or the
         mapped type if they are different
        """
        # special treatment for array and map columns
        if "array" in col_type or "map" in col_type:
            col_type = col_type.replace("<", "(").replace(">", ")")
            # splits by ',' '(' and ')', keeping delimiters
            str_parts = re.split(r"([,|\(|\)])", col_type)
            new_type = ""
            for str_part in str_parts:
                new_type += self._get_base_col_mapping(str_part)
            return new_type
        else:
            return self._get_base_col_mapping(col_type)

    def _validate_table_schema_match(self, spark_ms_table_columns, trino_table_schema):
        return self._compare_tables_schema_length(
            spark_ms_table_columns, trino_table_schema
        ) and self._compare_tables_schema_columns(
            spark_ms_table_columns, trino_table_schema
        )

    def validate_partition_values_count(self):
        spark_metastore_service = SparkMetastoreService(SparkClient())
        partition_keys = spark_metastore_service.get_table_partition_keys(
            self.database_name, self.table_name
        )
        if not partition_keys:
            logger.info(
                f"m={JOB_NAME}, database={self.database_name}, table={self.table_name}, "
                "msg=The table is not partitioned, skipping the partition values validation."
            )
            return True

        databricks_consumer = DatabricksConsumer(
            {"db": self.database_name}, SparkClient()
        )
        spark_partition_values = databricks_consumer.get_partition_values_from_table(
            table_name=self.table_name
        )
        spark_partition_values_count = len(spark_partition_values.collect())

        query = (
            f'SELECT count(1) FROM {self.database_name}."{self.table_name}$partitions"'
        )
        trino_partition_values_count = self.trino_client.get_records(query)

        if spark_partition_values_count != trino_partition_values_count[0][0]:
            msg = (
                f"database={self.database_name}, table={self.table_name}"
                "\n\nMessage=The partition values count of the table in In-house Hive and Spark metastores are diverging."
            )
            notify_error_in_slack(msg)
            logger.error(f"m={JOB_NAME}, {msg}")
            return False

        logger.info(
            f"m={JOB_NAME}, database={self.database_name}, table={self.table_name}, "
            "msg=Table partitions values match."
        )
        return True

    def validate_content(self):
        databricks_consumer = DatabricksConsumer(
            {"db": self.database_name}, SparkClient()
        )
        spark_table_count = databricks_consumer.get_data_from_query(
            f"SELECT count(1) FROM {self.database_name}.{self.table_name}"
        )
        spark_table_count = spark_table_count.collect()[0][0]

        trino_table_count = self.trino_client.get_records(
            f"SELECT count(1) FROM {self.database_name}.{self.table_name}"
        )
        trino_table_count = trino_table_count[0][0]

        if spark_table_count != trino_table_count:
            msg = (
                f"database={self.database_name}, table={self.table_name}, trino_count={trino_table_count},"
                f" spark_count={spark_table_count}\n\nMessage=The content of table in In-house Hive and Spark "
                "metastores are diverging."
            )
            notify_error_in_slack(msg)
            logger.error(f"m={JOB_NAME}, {msg}")
            return False

        logger.info(
            f"m={JOB_NAME}, database={self.database_name}, table={self.table_name}, "
            "msg=Table counts match."
        )
        return True


def validate_table_arguments(_table_name, _all_tables):
    """
    Verifies if the job is called exclusively for validating the sync of a
     unique table or all of them.

    :param _table_name: the table to be validated
    :type _table_name: str
    :param _all_tables: flag indicating to validate all tables of giving database
    :type _all_tables: bool (received as string though)
    :rtype: bool
    """
    if bool(_table_name) == bool(_all_tables):
        msg = (
            f"table_name={_table_name}, all_tables={_all_tables}"
            "\n\nMessage=Parameters table_name and all_tables should be mutual exclusive."
        )
        notify_error_in_slack(msg)
        logger.error(f"m={JOB_NAME}, {msg}")
        return False
    return True


def get_database_name(_db_name_part, _layer):
    """
    Gets the Spark and In-house metastores databases metadata for given layer.

    :param _db_name_part: The `source` name for raw and clean layers. Or the
     `source` and/or `context` name for enrich layer. The `schema` for DW layer.
    :type _db_name_part: str
    :param _layer: one of LayerEnum values
    :type _layer: str
    :return:
    """
    if _layer == LayerEnum.DW.value:
        dw_ms_mapping = DwMetastoreMapping(
            schema=_db_name_part, bucket=""
        ).get_all_dw_info()

        _spark_database_name = dw_ms_mapping["dw_schema_databricks"]
    else:
        dl_ms_mapping = DatalakeMetastoreMapping(source=_db_name_part, bucket="")

        _spark_database_name, _ = dl_ms_mapping.get_datalake_info_from_layer(_layer)

    return _spark_database_name


def get_spark_metastore_table_names(database_name):
    """
    Query the Spark metastore to get all the table names for given database.

    :param database_name: database name
    :type database_name: str
    :return: List[str]
    """
    databricks_consumer = DatabricksConsumer({"db": database_name}, SparkClient())
    df_databricks_tables = databricks_consumer.get_table_names_and_sizes()
    return [row.table_name for row in df_databricks_tables.collect()]


def get_trino_conn_conf():
    """
    Retrieves the Hive Metastore host stored in databricks secrets

    :rtype: json
    """
    trino_confs = dbutils.secrets.get("quintoandar", DatabaseEnum.TRINO)  # noqa: F821
    trino_confs_json = json.loads(trino_confs)
    return trino_confs_json


def get_slack_dae_webhook():
    """
    Get webook for channel squad-data-availability

    :return: str
    """
    return dbutils.secrets.get("quintoandar", "SLACK_DAE_WEBHOOK")  # noqa: F821


def notify_error_in_slack(msg):
    """
    Alternative flow to post a message to squad-data-availability

    :param msg: the error message
    :type msg: str
    """
    logger.error(f"m={JOB_NAME}, {msg}")

    webhook = get_slack_dae_webhook()
    if webhook:
        requests.post(
            webhook,
            json={
                "text": f":alert: Job validate_sync_metastore_tables has failed.\n```{msg}```"
            },
        )


def parse_args():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("layer_value", type=str, help="One of LayerEnum values")
    parser.add_argument(
        "db_name_part",
        type=str,
        help="The `source` name for raw and clean layers. The `source` and/or "
        "`context` name for enrich layer. The `schema` for DW layer.",
    )
    parser.add_argument(
        "--table-name",
        type=str,
        dest="table_name",
        required=False,
        help="table name for single sync",
    )
    parser.add_argument(
        "--all-tables",
        nargs="?",
        dest="all_tables",
        required=False,
        default=False,
        const=True,
        help="sync all tables from database",
    )

    args = parser.parse_args()
    _layer_value = args.layer_value
    _db_name_part = args.db_name_part
    _table_name = args.table_name
    _all_tables = args.all_tables

    return _layer_value, _db_name_part, _table_name, _all_tables


def start_spark_job():
    """ Main method. """
    layer_value, db_name_part, table_name, all_tables = parse_args()
    if not validate_table_arguments(table_name, all_tables):
        return False

    layer = LayerEnum(layer_value).value

    logger.info(
        f"m={JOB_NAME} layer={layer}, db_name_part={db_name_part}, "
        f"table_name={table_name}, all_tables={all_tables}, msg=Job execution started."
    )

    database_name = get_database_name(db_name_part, layer)

    table_names = []
    if all_tables:
        table_names = get_spark_metastore_table_names(database_name=database_name)
    else:
        table_names.append(table_name)

    for table in table_names:
        MetastoreSyncValidation(
            database_name, table, get_trino_conn_conf()
        ).validate_table()


if __name__ == "__main__":
    start_spark_job()
