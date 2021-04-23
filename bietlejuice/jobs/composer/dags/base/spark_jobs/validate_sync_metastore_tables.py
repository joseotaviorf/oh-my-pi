"""
    Validates the synchronization between in-house metastore and Databricks metastore.

    It will validate:
        - table schema
        - partition keys
        - partition values count
        - table content count (<<<deactivate temporarily>>>)

    Obs.: This job is temporary and will be removed after the sync implementation is finished for all tables.
"""
import json
import logging
import re
from argparse import ArgumentParser

import requests
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatabaseEnum
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreMapping
from bietlejuice.jobs.composer.base.db.dw_metastore_mapping import DwMetastoreMapping
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.base.spark import BaseSparkContext
from bietlejuice.jobs.composer.clients.db_clients import SparkClient, TrinoClient
from bietlejuice.jobs.composer.consumers.db_consumers.databricks_consumer import (
    DatabricksConsumer,
)
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

JOB_NAME = "validate_sync_metastore_tables"

logging.getLogger("py4j").setLevel(logging.ERROR)


class SparkMetastoreHelper:
    def __init__(
        self, layer, db_name_part, table_name, all_tables, slack_webhook
    ) -> None:
        self.layer = layer
        self.db_name_part = db_name_part
        self.table_name = table_name
        self.all_tables = all_tables
        self.spark_database_name = self.get_spark_database_name()
        self.spark_client = SparkClient()
        self.spark_metastore_service = SparkMetastoreService(self.spark_client)
        self.slack_webhook = slack_webhook

    def get_spark_database_name(self):
        """
        Gets the Spark and In-house metastores databases metadata for given layer.

        :return: the database name in Spark metastore
        """
        if self.layer == LayerEnum.DW.value:
            dw_ms_mapping = DwMetastoreMapping(
                schema=self.db_name_part, bucket=""
            ).get_all_dw_info()

            spark_database_name = dw_ms_mapping["dw_schema_databricks"]
        else:
            dl_ms_mapping = DatalakeMetastoreMapping(
                source=self.db_name_part, bucket=""
            )

            spark_database_name, _ = dl_ms_mapping.get_datalake_info_from_layer(
                self.layer
            )

        return spark_database_name

    def validate_table_arguments(self):
        """
        Verifies if the job is called exclusively for validating the sync of a
         unique table or all of them.

        :rtype: bool
        """
        if bool(self.table_name) == bool(self.all_tables):
            msg = (
                ">*Message: `Parameters table_name and all_tables should be mutual exclusive.`*\n"
                f">*_table_name_:* `{self.table_name}`\n"
                f">*_all_tables_:* `{self.all_tables}`"
            )
            notify_error_in_slack(self.slack_webhook, msg)
            QuintoAndarLogger(JOB_NAME).error(f"m={JOB_NAME}, {msg}")

            return False

        return True

    def get_table_names(self):
        """
        Returns the table names to be validated according to the job arguments.

        If the argument `all_tables` was defined, them all tables of that database
        will be returned, else the given argument `table_name` will be used as the
        table.

        :rtype: list
        """
        table_names = []
        if self.all_tables:
            table_names = self.get_spark_metastore_table_names()
        else:
            table_names.append(self.table_name)

        return table_names

    def get_spark_metastore_table_names(self):
        """
        Query the Spark metastore to get all the table names for given database.

        :return: List[str]
        """
        databricks_consumer = DatabricksConsumer(
            {"db": self.spark_database_name}, self.spark_client
        )
        df_databricks_tables = databricks_consumer.get_table_names_and_sizes()
        return [row.table_name for row in df_databricks_tables.collect()]

    def get_table_schema_with_partition_keys(self, table_name):
        """
        Gets the table schema in the Spark metastore.
        The schema list contains the columns and the partition keys.

        :param table_name: target table
        :return: table columns and partition keys
        :rtype: collections.OrderedDict[(string, string)]
        """
        spark_ms_table_schema = self.spark_metastore_service.get_table_schema(
            self.spark_database_name, table_name
        )
        self._validate_empty_table_schema(table_name, spark_ms_table_schema)

        if LayerEnum.RAW.value in self.spark_database_name:
            spark_ms_table_schema = self._set_timestamps_as_string(
                spark_ms_table_schema
            )

        return spark_ms_table_schema

    def _validate_empty_table_schema(self, table_name, table_schema):
        if not table_schema:
            raise AssertionError(
                f"m={JOB_NAME}, database={self.spark_database_name}, table={table_name}, "
                "msg=The table has an empty schema in the Spark metastore."
            )

    @staticmethod
    def _set_timestamps_as_string(_spark_ms_table_columns):
        """
        Forcefully set the timestamp columns to string.

        Some json data in Spark Metastore raw tables are automatically interpreted
         as timestamp and the date part is automatically extracted when we select data.
         For example, for the raw data {"revision_date":"{\"$date\": \"2021-01-10T00:00:00.157Z\"}"}
         the command `select revision_date from table_a` will return `2021-01-10T00:00:00.157Z`
         instead of the full json content with the key `$date`.
        The Hive Metastore does not automatically extract the date part for the timestamp columns
          but raises a parse error instead.

        :param _spark_ms_table_columns: the spark columns schema
        :return: columns with timestamps as string
        :rtype: collections.OrderedDict[(string, string)]
        """
        for col in _spark_ms_table_columns:
            _spark_ms_table_columns[col] = _spark_ms_table_columns[col].replace(
                "timestamp", "string"
            )

        return _spark_ms_table_columns

    def get_table_partition_values_count(self, table_name):
        """
        Gets the partition values count for the table in Spark metastore

        :param table_name: target table name
        :rtype: int
        """
        databricks_consumer = DatabricksConsumer(
            {"db": self.spark_database_name}, self.spark_client
        )
        spark_partition_values = databricks_consumer.get_partition_values_from_table(
            table_name=table_name
        )

        return len(spark_partition_values.collect())

    def get_table_count(self, table_name):
        """
        Gets the table count in Spark metastore
        :rtype: int
        """
        databricks_consumer = DatabricksConsumer(
            {"db": self.spark_database_name}, self.spark_client
        )
        spark_table_count = databricks_consumer.get_data_from_query(
            f"SELECT count(1) FROM {self.spark_database_name}.{table_name}"
        )
        return spark_table_count.collect()[0][0]

    def get_all_tables_metadata(self):
        """
        Fetches all database tables metadata.
        This metadata will be shared during the parallelized processing of table names RDD.

        :return: table schema and partition information
        :rtype: dict
        """
        tables_spark_metadata = dict()
        for table_name in self.get_table_names():
            spark_ms_table_schema = self.get_table_schema_with_partition_keys(
                table_name
            )
            spark_msg_table_partition_keys = self.spark_metastore_service.get_table_partition_keys(
                self.spark_database_name, table_name
            )

            spark_msg_table_partition_values_count = 0
            if spark_msg_table_partition_keys:
                spark_msg_table_partition_values_count = self.get_table_partition_values_count(
                    table_name
                )

            # spark_table_count = self.get_table_count(table_name)

            tables_spark_metadata[table_name] = dict()
            tables_spark_metadata[table_name]["name"] = table_name
            tables_spark_metadata[table_name]["schema"] = spark_ms_table_schema
            tables_spark_metadata[table_name][
                "partition_keys"
            ] = spark_msg_table_partition_keys
            tables_spark_metadata[table_name][
                "partition_values_count"
            ] = spark_msg_table_partition_values_count
            # tables_spark_metadata[table_name]["rows_count"] = spark_table_count

        return tables_spark_metadata


class HiveMetastoreSyncValidation:
    SPARK_TO_TRINO_COLUMN_TYPE = {
        "string": "varchar",
        "int": "integer",
        "timestamp": "timestamp(3)",
        "float": "real",
        "struct": "row",
    }

    def __init__(self, database_name, trino_client, slack_webhook) -> None:
        """
        Constructor.

        :param database_name: target database name
        :param table_name: target table that will be validated
        """
        self.database_name = database_name
        self.trino_client = trino_client
        self.slack_webhook = slack_webhook
        self.table_name = None

    def validate_table(self, table_metadata):
        self.table_name = table_metadata["name"]
        if (
            self.validate_schema_and_partition_keys(table_metadata["schema"])
            and self.validate_partition_values_count(
                table_metadata["partition_keys"],
                table_metadata["partition_values_count"],
            )
            # temporarily removed due to Trino issue with the count command
            # and self.validate_content_count(table_metadata["rows_count"])
        ):
            QuintoAndarLogger(JOB_NAME).info(
                f"m={JOB_NAME}, database={self.database_name}, table={self.table_name}, "
                f"msg=Table synchronization validation succeeded."
            )

    def validate_schema_and_partition_keys(self, spark_table_schema):
        """
        Gets and compares the table schema in Spark and In-house metastores.
         The partition keys are included in the schema comparison.

        :rtype: bool
        """
        trino_table_schema = self.execute_trino_query(
            query=f'DESCRIBE {self.database_name}."{self.table_name}"'
        )
        if not trino_table_schema:
            return False

        self._validate_empty_table_schema(trino_table_schema)
        trino_table_schema = self._parse_trino_schema(trino_table_schema)

        if not self._validate_table_schema_match(
            spark_table_schema, trino_table_schema
        ):
            msg = (
                ">*Message: `The schema of the table in In-house Hive and Spark metastores are diverging.`*\n"
                f">*Database:* `{self.database_name}`\n"
                f">*Table:* `{self.table_name}`"
            )
            notify_error_in_slack(self.slack_webhook, msg)
            return False

        QuintoAndarLogger(JOB_NAME).info(
            f"m={JOB_NAME}, database={self.database_name}, table={self.table_name}, "
            "msg=Table schemas and partition keys match."
        )
        return True

    def execute_trino_query(self, query):
        """
        Securely performs the Trino query.
        In case of a Trino error, avoids the job to fail and logs the error message.

        :type query: str
        :return: the query result or False in case of error
        :rtype: mixed
        """
        try:
            return self.trino_client.get_records(query)
        except Exception as e:
            msg = (
                f">*Message: `Error fetching data in Trino: {e.message}`*\n"
                f">*Database:* `{self.database_name}`\n"
                f">*Table:* `{self.table_name}`\n"
                f">*Query:* `{query}`"
            )
            notify_error_in_slack(self.slack_webhook, msg)
            QuintoAndarLogger(JOB_NAME).error(f"m={JOB_NAME}, {msg}")
            return False

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
            QuintoAndarLogger(JOB_NAME).error(
                f"m={JOB_NAME}, database={self.database_name}, table={self.table_name}, "
                f"spark_col_number={len(spark_ms_table_columns)} trino_col_numer={len(trino_table_schema)},"
                " msg=The tables have different column count."
            )
            return False

        return True

    @staticmethod
    def _remove_special_chars_from_column(column_value):
        """
        Removes special chars from column value.
        Special chars being removed: space(" ") and colon (:)

        :param column_value: value to be applied regexp replace
        :type column_value: string
        :return: formatted value
        :rtype: string
        """
        return re.sub(" |:", "", column_value)

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
            if (col_name.lower() not in trino_table_schema.keys()) or (
                self._remove_special_chars_from_column(
                    trino_table_schema[col_name.lower()]
                )
                != self._remove_special_chars_from_column(
                    self._get_spark_to_trino_col_mapping(col_type)
                )
            ):
                QuintoAndarLogger(JOB_NAME).error(
                    f"m={JOB_NAME}, database={self.database_name}, table={self.table_name}, "
                    f"column={col_name.lower()}, msg=The column diverges in both Metastore tables."
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

    def validate_partition_values_count(
        self, spark_patition_keys, spark_partition_values_count
    ):
        if not spark_patition_keys:
            QuintoAndarLogger(JOB_NAME).info(
                f"m={JOB_NAME}, database={self.database_name}, table={self.table_name}, "
                "msg=Skipping the partition values validation: the table is not partitioned."
            )
            return True

        trino_partition_values_count = self.execute_trino_query(
            query=f'SELECT count(1) FROM {self.database_name}."{self.table_name}$partitions"'
        )
        if not trino_partition_values_count:
            return False

        if spark_partition_values_count != trino_partition_values_count[0][0]:
            msg = (
                ">*Message: `The partition values count of the table in In-house Hive and Spark metastores are diverging.`*\n"
                f">*Database:* `{self.database_name}`\n"
                f">*Table:* `{self.table_name}`"
            )
            notify_error_in_slack(self.slack_webhook, msg)
            QuintoAndarLogger(JOB_NAME).error(f"m={JOB_NAME}, {msg}")
            return False

        QuintoAndarLogger(JOB_NAME).info(
            f"m={JOB_NAME}, database={self.database_name}, table={self.table_name}, "
            "msg=Table partitions values match."
        )
        return True

    def validate_content_count(self, spark_table_count):
        trino_table_count = self.execute_trino_query(
            query=f'SELECT count(1) FROM {self.database_name}."{self.table_name}"'
        )
        if not trino_table_count:
            return False

        if spark_table_count != trino_table_count[0][0]:
            msg = (
                f">*Message: `The count of table in In-house Hive and Spark metastores are diverging.`*\n"
                f">*Spark count:* `{spark_table_count}`\n"
                f">*Trino count:* `{trino_table_count}`\n"
                f">*Database:* `{self.database_name}`\n"
                f">*Table:* `{self.table_name}`"
            )
            notify_error_in_slack(self.slack_webhook, msg)
            QuintoAndarLogger(JOB_NAME).error(f"m={JOB_NAME}, {msg}")
            return False

        QuintoAndarLogger(JOB_NAME).info(
            f"m={JOB_NAME}, database={self.database_name}, table={self.table_name}, "
            "msg=Table counts match."
        )
        return True


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


def notify_error_in_slack(slack_webhook, msg_log):
    """
    Alternative flow to post a message to squad-data-availability

    :param msg_log: the error message
    :type msg_log: str
    """
    QuintoAndarLogger(JOB_NAME).error(f"m={JOB_NAME}, {msg_log}")

    if slack_webhook:
        requests.post(
            slack_webhook,
            json={
                "text": f":warning: Job *_validate_sync_metastore_tables_* has failed.\n\n\n*Error log:*\n{msg_log}"
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
    layer = LayerEnum(layer_value).value

    QuintoAndarLogger(JOB_NAME).info(
        f"m={JOB_NAME} layer={layer}, db_name_part={db_name_part}, "
        f"table_name={table_name}, all_tables={all_tables}, msg=Job execution started."
    )

    slack_webhook = get_slack_dae_webhook()
    spark_ms = SparkMetastoreHelper(
        layer, db_name_part, table_name, all_tables, slack_webhook
    )
    if not spark_ms.validate_table_arguments():
        return False

    tables_metadata = spark_ms.get_all_tables_metadata()
    spark_table_names = list(tables_metadata.keys())

    trino_conn_config = get_trino_conn_conf()
    trino_client = TrinoClient(
        trino_conn_config["host"], trino_conn_config["port"], trino_conn_config["user"]
    )

    hms_sync_validation = HiveMetastoreSyncValidation(
        spark_ms.spark_database_name, trino_client, slack_webhook
    )
    tables_rdd = BaseSparkContext.sc.parallelize(spark_table_names)
    tables_rdd.foreach(
        lambda _table_name: hms_sync_validation.validate_table(
            tables_metadata.get(_table_name)
        )
    )

    QuintoAndarLogger(JOB_NAME).info(f"m={JOB_NAME}, msg=Validations finished.")


if __name__ == "__main__":
    start_spark_job()
