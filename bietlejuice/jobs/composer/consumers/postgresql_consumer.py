from pyspark.sql import SparkSession
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatabaseTypeEnum
from bietlejuice.jobs.composer.consumers.database_consumer import DatabaseConsumer

logger = QuintoAndarLogger("PostgreSQLConsumer")


class PostgreSQLConsumer(DatabaseConsumer):
    FETCH_SIZE = 50000

    def __init__(self, connection):
        if connection["dbtype"].lower() != DatabaseTypeEnum.POSTGRESQL:
            raise RuntimeError(
                "m=__init__, con_type={}, msg=Connection is not a postgresql"
                "connection".format(connection.get("dbtype"))
            )

        connection["url"] = "jdbc:postgresql://{}:{}/{}".format(
            connection["host"], connection["port"], connection["db"]
        )
        connection["driver"] = "org.postgresql.Driver"
        if "schema" not in connection:
            connection["schema"] = "public"

        self.connection = connection

    @logger
    def get_table_names_and_sizes(self):
        query = """
            SELECT
                table_name as table,
                pg_relation_size(quote_ident(table_name)) / 1024 / 1024 AS size
            FROM
                information_schema.tables
            WHERE
                table_schema = '{schema}'
            ORDER BY
                size DESC
        """
        result = self.get_data_from_query(
            query.format(schema=self.connection["schema"])
        )

        return result

    @logger
    def get_data_from_table(self, table):
        remote_table = (
            self._get_default_read_format_and_options()
            .option("dbtable", self.connection["schema"] + "." + table)
            .load()
        )

        return remote_table

    @logger
    def get_data_from_table_in_parallel(self, table, concurrency):
        remote_table = self._get_default_read_format_and_options()

        partition_column = self._get_partition_column_from_table(table)

        if partition_column:
            query = "select max({}) from {}".format(partition_column, table)
            result = self.get_data_from_query(query)
            upper_bound = result.collect()[0][0]

            query = "select min({}) from {}".format(partition_column, table)
            result = self.get_data_from_query(query)
            lower_bound = result.collect()[0][0]

            remote_table = (
                remote_table.option("partitionColumn", partition_column)
                .option("lowerBound", lower_bound)
                .option("upperBound", upper_bound)
                .option("numPartitions", concurrency)
            )

        remote_table = remote_table.option(
            "dbtable", self.connection["schema"] + "." + table
        ).load()

        return remote_table

    @logger
    def get_data_from_query(self, query):
        remote_table = (
            self._get_default_read_format_and_options().option("query", query).load()
        )
        return remote_table

    @logger
    def get_table_schema(self, table):
        query = """
            SELECT
                column_name, data_type as column_type
            FROM
                information_schema.columns
            WHERE
                table_name = '{table}'
        """

        result = self.get_data_from_query(
            query.format(table=self.connection["schema"] + "." + table)
        )

        return result

    @logger
    def _get_default_read_format_and_options(self):
        spark = SparkSession.builder.getOrCreate()

        return (
            spark.read.format("jdbc")
            .option("driver", self.connection["driver"])
            .option("fetchsize", self.FETCH_SIZE)
            .option("url", self.connection["url"])
            .option("user", self.connection["user"])
            .option("password", self.connection["pwd"])
        )

    @logger
    def _get_partition_column_from_table(self, table):
        query = """
            SELECT
                pg_attribute.attname as COLUMN_NAME,
                format_type(pg_attribute.atttypid, pg_attribute.atttypmod),
                reltuples as cardinality
            FROM
                pg_index,
                pg_class,
                pg_attribute,
                pg_namespace
            WHERE
                pg_class.oid = '{table}'::regclass AND
                indrelid = pg_class.oid AND
                nspname = '{schema}' AND
                pg_class.relnamespace = pg_namespace.oid AND
                pg_attribute.attrelid = pg_class.oid AND
                pg_attribute.attnum = any(pg_index.indkey) AND
                indisprimary
            ORDER BY
                cardinality DESC
        """

        df = self.get_data_from_query(
            query.format(
                db=self.connection["db"], table=table, schema=self.connection["schema"]
            )
        ).select("COLUMN_NAME")

        if df.count():
            return df.collect()[0][0]

        logger.warning(
            "m=_get_partition_column_from_table, table={}, msg=Partition column "
            "to parallelize the table read was not found.".format(table)
        )
