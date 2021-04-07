from datetime import datetime, timedelta

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatabaseTypeEnum
from bietlejuice.jobs.composer.consumers.db_consumers.db_consumer import DBConsumer

logger = QuintoAndarLogger("PostgresConsumer")


class PostgresConsumer(DBConsumer):
    """
    Gets data from a Postgres database through Spark and returns it as a Spark
    DataFrame.
    :param conn_config: A dict with the config values of the connection. It must
    contain the keys: host, port, db, user, and pwd.
    :type conn_config: dict
    :param spark_client: A client to handle the Spark connection
    :type spark_client: SparkClient
    :param fetch_size: The JDBC fetch size, which determines how many rows to fetch
    per round trip. This can help performance on JDBC drivers which default to low
    fetch size (eg. Oracle with 10 rows). This option applies only to reading.
    :type fetch_size: int
    """

    # todo: rename this class in a way we can allow other Postgres consumer types (e.g.,
    #  Pandas consumer, PETL consumer). Examples of the new class names could be
    #  PostgresSparkConsumer or SparkPostgresConsumer.
    def __init__(self, conn_config, spark_client, fetch_size=50000):
        # todo: investigate further about an optimal value for the fetch_size param
        if conn_config["dbtype"].lower() != DatabaseTypeEnum.POSTGRESQL:
            raise RuntimeError(
                "m=__init__, con_type={}, msg=Connection is not a PostgreSql"
                "connection".format(conn_config.get("dbtype"))
            )

        self.conn_config = conn_config
        if "schema" not in self.conn_config:
            self.conn_config["schema"] = "public"
        self.spark_client = spark_client
        self.spark_common_options = {
            "driver": "org.postgresql.Driver",
            "fetchsize": fetch_size,
            "url": "jdbc:postgresql://{}:{}/{}".format(
                self.conn_config["host"],
                self.conn_config["port"],
                self.conn_config["db"],
            ),
            "user": self.conn_config["user"],
            "password": self.conn_config["pwd"],
        }

    @logger
    def get_table_names_and_sizes(self):
        """
        Gets the table names and sizes in MB of a PostgreSql database.
        :return: A Spark DataFrame with cols: table_name and size
        """
        query = """
            SELECT
                table_name,
                pg_relation_size('"{schema}".' || quote_ident(
                table_name)) / 1024 / 1024 AS size
            FROM
                information_schema.tables
            WHERE
                table_schema = '{schema}'
            ORDER BY
                size DESC
        """.format(
            schema=self.conn_config["schema"]
        )
        df = self.get_data_from_query(query)

        return df

    @logger
    def get_data_from_table(self, table_name):
        """
        Gets all data from a table in a PostgreSql database.
        :param table_name: Name of the table
        :return: A Spark DataFrame with the table data
        """
        extended_table_name = self.conn_config["schema"] + '."' + table_name + '"'
        df = self.spark_client.get_data_from_external_source(
            format="jdbc",
            options={**self.spark_common_options, "dbtable": extended_table_name},
        )

        return df

    @logger
    def get_data_from_table_in_parallel(self, table_name, concurrency):
        """
        Gets all data from a table in parallel in a PostgreSql Database.
        :param table_name: Name of the table
        :param concurrency: Number of tasks that are launched to read the data
        :return: A Spark DataFrame with the table data
        """
        # todo: explain in the method doc the strategy to use when reading from a
        #  table in parallel
        partition_column = self._get_partition_column_from_table(table_name)
        extended_table_name = self.conn_config["schema"] + '."' + table_name + '"'

        if not partition_column:
            df = self.get_data_from_table(table_name)
        else:
            query = "select max({}) from {}".format(partition_column, table_name)
            df = self.get_data_from_query(query)
            upper_bound = df.collect()[0][0]

            query = "select min({}) from {}".format(partition_column, table_name)
            df = self.get_data_from_query(query)
            lower_bound = df.collect()[0][0]

            df = self.spark_client.get_data_from_external_source(
                format="jdbc",
                options={
                    **self.spark_common_options,
                    "dbtable": extended_table_name,
                    "partitionColumn": partition_column,
                    "lowerBound": lower_bound,
                    "upperBound": upper_bound,
                    "numPartitions": concurrency,
                },
            )

        return df

    @logger
    def get_data_from_query(self, query, table_name=None):
        """
        Gets the results of a query in a PostgreSql database.
        :param query: Query content
        :param table_name: Name of the table relevant to the query
        :return: A Spark DataFrame with the query results
        """
        df = self.spark_client.get_data_from_external_source(
            format="jdbc", options={**self.spark_common_options, "query": query}
        )

        return df

    @logger
    def get_table_schema(self, table_name):
        """
        Gets the schema of a table in a PostgreSql database.
        :param table_name: Name of a table
        :return: A Spark DataFrame with the table schema
        """
        extended_table_name = self.conn_config["schema"] + "." + table_name
        query = """
                SELECT
                    column_name as col_name,
                    data_type as col_type
                FROM
                    information_schema.columns
                WHERE
                    table_name = '{table}'
            """.format(
            table=extended_table_name
        )

        df = self.get_data_from_query(query)

        return df

    @logger
    def _get_partition_column_from_table(self, table_name):
        """
        Tries to find out a good partition column (a col with high cardinality) from a
        table.
        :param table_name: Name of a table
        :return: Column with higher cardinality or None if none is found.
        """
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
                    indisprimary AND
                    lower(
                        format_type(
                            pg_attribute.atttypid, pg_attribute.atttypmod
                        )
                    ) NOT LIKE '%character varying%' AND
                    reltuples > 0.0
                ORDER BY
                    cardinality DESC
            """.format(
            table=table_name, schema=self.conn_config["schema"]
        )

        df = self.get_data_from_query(query).select("COLUMN_NAME")

        if df.count():
            return df.collect()[0][0]

        logger.warning(
            "m=_get_partition_column_from_table, table={}, msg=Partition column "
            "to parallelize the table read was not found.".format(table_name)
        )

    @logger
    def get_incremental_data_from_table(
        self, table_name, date_filter_column, date_filter_value, is_unixtime_col=False
    ):
        """
        Gets incremental data from table in a Postgres database.
        The method expects a table and a date/timestamp or unix timestamp
        column to make the filter.
        :param table_name: Name of the table
        :param date_filter_column: Name of the column to make the filter
        :param date_filter_value: Value of the column
        :param is_unixtime_col: Boolean to be seted True when the date_filter_column
        has a unix timestamp date_filter_value.
        :return: A Spark DataFrame with the table data
        """

        schema = self.conn_config["schema"]

        dt_filter_value = datetime.strptime(date_filter_value, "%Y-%m-%d")
        dt_filter_value_day_after = dt_filter_value + timedelta(days=1)

        if is_unixtime_col:
            filter_value = int(dt_filter_value.timestamp())
            filter_value_day_after = int(dt_filter_value_day_after.timestamp())
            filter_enclosement = "{filter}"
        else:
            filter_value = dt_filter_value
            filter_value_day_after = dt_filter_value_day_after
            filter_enclosement = "'{filter}'"

        query_filter_value = filter_enclosement.format(filter=filter_value)
        query_filter_value_day_after = filter_enclosement.format(
            filter=filter_value_day_after
        )

        # The query verifies if the value of the column is between start_date and end_date.
        # Also, it handles when the column is a timestamp or/and string.
        query = f"""
            SELECT
                *,
                {dt_filter_value.year} AS year,
                {dt_filter_value.month} AS month,
                {dt_filter_value.day} AS day
            FROM
                "{schema}"."{table_name}"
            WHERE
                {date_filter_column} >= {query_filter_value}
                AND {date_filter_column} < {query_filter_value_day_after}
                """

        return self.get_data_from_query(query)
