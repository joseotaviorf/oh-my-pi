from datetime import datetime, timedelta
import textwrap

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db.database_driver_enum import DatabaseDriverEnum
from bietlejuice.consumers.db_consumers.db_consumer import DBConsumer

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

    _DATABASE_DRIVERS = [DatabaseDriverEnum.POSTGRES, DatabaseDriverEnum.REDSHIFT]
    _JDBC_URL_MAPPING = {
        DatabaseDriverEnum.POSTGRES: "postgresql",
        DatabaseDriverEnum.REDSHIFT: "redshift",
    }

    # todo: rename this class in a way we can allow other Postgres consumer types (e.g.,
    #  Pandas consumer, PETL consumer). Examples of the new class names could be
    #  PostgresSparkConsumer or SparkPostgresConsumer.
    def __init__(self, conn_config, spark_client, fetch_size=50000):
        dbtype = conn_config["dbtype"]
        driver_enum = DatabaseDriverEnum[dbtype.upper()]

        if driver_enum not in self._DATABASE_DRIVERS:
            raise RuntimeError(
                f"m=__init__, db_type={dbtype}, msg=Connection is not a "
                "PostgreSql connection"
            )
        self.conn_config = conn_config
        self.conn_config["schema"] = self.conn_config.get("schema", "public")
        self.spark_client = spark_client
        self.spark_common_options = {
            "driver": driver_enum.value,
            "fetchsize": fetch_size,
            "url": "jdbc:{}://{}:{}/{}".format(
                self._JDBC_URL_MAPPING[driver_enum],
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
                table_name AS table_name,
                pg_relation_size('"{schema}".' || quote_ident(
                table_name)) / 1024 / 1024 AS size
            FROM
                information_schema.tables
            WHERE
                table_schema = '{schema}'
                AND table_name NOT IN (
                    'change_owner_control',
                    'flyway_schema_history',
                    'pg_buffercache',
                    'pg_stat_statements',
                    'schema_migrations'
                )
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
        query = f"""
            SELECT
                column_name AS col_name,
                data_type AS col_type,
                COALESCE(character_maximum_length, numeric_precision) AS col_length,
                numeric_scale AS col_scale
            FROM
                information_schema.columns
            WHERE
                table_schema = '{self.conn_config["schema"]}'
                AND table_name = '{table_name}'
        """

        df = self.get_data_from_query(textwrap.dedent(query))

        return df

    @logger
    def get_table_primary_keys(self, table_name):
        """
        Gets the primary keys of a table in a PostgreSql database.
        :param table_name: Name of a table
        :return: A list with the primary keys of the table
        """
        query = f"""
            SELECT
                a.attname as col_name
            FROM
                pg_index i
            JOIN
                pg_attribute a ON a.attrelid = i.indrelid
                AND a.attnum = ANY(i.indkey)
            WHERE
                i.indrelid = '{self.conn_config["schema"]}.{table_name}'::regclass
                AND i.indisprimary
        """

        df = self.get_data_from_query(textwrap.dedent(query))
        return [row.col_name for row in df.collect()]

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
        self, table_name, date_filter_column, date_filter_value, unixtime_measure=None
    ):
        """
        Gets incremental data from table in a Postgres database.
        The method expects a table and a date/timestamp or unix timestamp
        column to make the filter.
        :param table_name: Name of the table
        :param date_filter_column: Name of the column to make the filter
        :param date_filter_value: Value of the column
        :param unixtime_measure: String to indicate if the column filter will be in seconds or milliseconds.
        has a unix timestamp date_filter_value.
        :return: A Spark DataFrame with the table data
        """

        schema = self.conn_config["schema"]

        dt_filter_value = datetime.strptime(date_filter_value, "%Y-%m-%d")
        dt_filter_value_day_after = dt_filter_value + timedelta(days=1)

        if unixtime_measure == "milliseconds":
            filter_value = 1000 * int(dt_filter_value.timestamp())
            filter_value_day_after = 1000 * int(dt_filter_value_day_after.timestamp())
        elif unixtime_measure == "seconds":
            filter_value = int(dt_filter_value.timestamp())
            filter_value_day_after = int(dt_filter_value_day_after.timestamp())
        else:
            filter_value = dt_filter_value
            filter_value_day_after = dt_filter_value_day_after

        filter_enclosement = (
            "{filter}" if unixtime_measure is not None else "'{filter}'"
        )
        query_filter_value = filter_enclosement.format(filter=filter_value)
        query_filter_value_day_after = filter_enclosement.format(
            filter=filter_value_day_after
        )

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

    @logger
    def get_incremental_data_by_granularity_from_table(
        self,
        table_name,
        date_filter_column,
        date_filter_value,
        unixtime_measure=None,
        partition_granularity="day",
    ):
        """
        Gets incremental data from table in a Postgres database.
        The method expects a table and a date/timestamp or unix timestamp
        column to make the filter. Disclaimer: This method doesn't make use from our
        postgresql indexes
        :param table_name: Name of the table
        :param date_filter_column: Name of the column to make the filter
        :param date_filter_value: Value of the column
        :param unixtime_measure: unix time measure to be seted as milliseconds or seconds
        :param partition_granularity: Granularity which the date column will be
        truncated to fetch the partition data - default value 'day'
        :return: A Spark DataFrame with the table data
        """

        if partition_granularity not in ["day", "month", "year"]:
            raise Exception(
                "m=get_incremental_data_from_table, "
                f"partition_granularity={partition_granularity}, "
                "msg=Wrong truncate condition."
            )

        schema = self.conn_config["schema"]

        dt_filter_value = datetime.strptime(date_filter_value, "%Y-%m-%d")

        if unixtime_measure == "milliseconds":
            date_filter_column = f"TO_TIMESTAMP({date_filter_column}/1000)"
        elif unixtime_measure == "seconds":
            date_filter_column = f"TO_TIMESTAMP({date_filter_column})"

        filter_condition = (
            f"DATE_TRUNC('{partition_granularity}',DATE({date_filter_column})) = "
            f"DATE_TRUNC('{partition_granularity}', DATE('{dt_filter_value}'))"
        )

        query = f"""
            SELECT
                *,
                CAST(EXTRACT(YEAR FROM DATE({date_filter_column})) AS INT) AS year,
                CAST(EXTRACT(MONTH FROM DATE({date_filter_column})) AS INT) AS month,
                CAST(EXTRACT(DAY FROM DATE({date_filter_column})) AS INT) AS day
            FROM
                "{schema}"."{table_name}"
            WHERE
                {filter_condition}
        """

        return self.get_data_from_query(query)

    @logger
    def get_incremental_data_by_processing_window(
        self,
        table_name,
        date_filter_column,
        load_start_date,
        load_end_date,
        unixtime_measure=None,
    ):
        """
        Gets incremental data from table in a Postgres database considering
        a time window for processing.
        The method expects a table and a date/timestamp or unix timestamp
        column to make the filter.
        :param table_name: Name of the table
        :param date_filter_column: Name of the column to make the filter
        :param load_start_date: Start date from which query will fetch data
        :param load_end_date: End date from which query will fetch data
        :param unixtime_measure: unix time measure to be seted as milliseconds or seconds

        :return: A Spark DataFrame with the table data
        """
        schema = self.conn_config["schema"]

        if unixtime_measure == "milliseconds":
            date_filter_column = f"TO_TIMESTAMP({date_filter_column}/1000)"
        elif unixtime_measure == "seconds":
            date_filter_column = f"TO_TIMESTAMP({date_filter_column})"

        query = f"""
        SELECT
            *,
            CAST(EXTRACT(YEAR FROM {date_filter_column}) as INT) AS year,
            CAST(EXTRACT(MONTH FROM {date_filter_column}) as INT) AS month,
            CAST(EXTRACT(DAY FROM {date_filter_column}) as INT) AS day
        FROM
            "{schema}"."{table_name}"
        WHERE
            {date_filter_column} >= DATE('{load_start_date}')
            AND {date_filter_column} < DATE(DATE('{load_end_date}') + INTERVAL '1 DAY')
        """

        query = textwrap.dedent(query)
        return self.get_data_from_query(query)
