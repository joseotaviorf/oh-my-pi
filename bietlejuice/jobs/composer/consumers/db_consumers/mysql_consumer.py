from datetime import datetime, timedelta
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatabaseTypeEnum
from bietlejuice.jobs.composer.consumers.db_consumers.db_consumer import DBConsumer

logger = QuintoAndarLogger("MySqlConsumer")


class MySqlConsumer(DBConsumer):
    """
    Gets data from a MySql database through Spark and returns it as a Spark
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

    # todo: rename this class in a way we can allow other MySql consumer types (e.g.,
    #  Pandas consumer, PETL consumer). Examples of the new class names could be
    #  MySqlSparkConsumer or SparkMySqlConsumer.

    def __init__(self, conn_config, spark_client, fetch_size=50000):
        # todo: investigate further about an optimal value for the fetch_size param
        if conn_config["dbtype"].lower() != DatabaseTypeEnum.MYSQL:
            raise RuntimeError(
                "m=__init__, con_type={}, msg=Connection is not a MySql"
                "connection".format(conn_config.get("dbtype"))
            )
        self.conn_config = conn_config
        self.spark_client = spark_client
        self.spark_common_options = {
            "driver": "com.mysql.jdbc.Driver",
            "fetchsize": fetch_size,
            "url": "jdbc:mysql://{}:{}/{}".format(
                self.conn_config["host"],
                self.conn_config["port"],
                self.conn_config["db"],
            ),
            "user": self.conn_config["user"],
            "password": self.conn_config["pwd"],
            "zeroDateTimeBehavior": "convertToNull",
        }

        if "params" in conn_config:
            params = [k + "=" + v for k, v in conn_config["params"].items()]
            params = "?" + "&".join(params)
            self.spark_common_options["url"] += params

    @logger
    def get_table_names_and_sizes(self):
        """
        Gets the table names and sizes of a MySql database.
        :return: A Spark DataFrame with cols: table_name and size
        """
        query = """
        SELECT
          table_name,
          round(((data_length + index_length) / 1024 / 1024), 2) AS `size`,
          TABLE_ROWS as rows_count
        FROM
          information_schema.TABLES
        where
          table_schema = '{db}'
        ORDER BY
          (data_length + index_length) DESC
        """.format(
            db=self.conn_config["db"]
        )

        df = self.get_data_from_query(query)

        return df

    @logger
    def get_data_from_table(self, table_name):
        """
        Gets all data from a table in a MySql database.
        :param table_name: Name of the table
        :return: A Spark DataFrame with the table data
        """
        df = self.spark_client.get_data_from_external_source(
            format="jdbc", options={**self.spark_common_options, "dbtable": table_name}
        )

        return df

    @logger
    def _get_partition_column_from_df(self, partitions_df, table_name):
        """
        Gets the column with highest cardinality from the partitions dataframe.
        :param table_name: Name of the table
        :param partitions_df: Data frame that contains all possible partitions for all database tables
        :return: The column name for the best reading partitioning, None if there is no good candidate
        """
        column_df = (
            partitions_df.filter(partitions_df.table_name == table_name)
            .sort(partitions_df.cadinality.desc())
            .first()
        )
        return column_df.column_name if column_df else None

    @logger
    def get_data_from_table_in_parallel(
        self, table_name, concurrency, partitions_df=None
    ):
        """
        Gets all data from a table in parallel in a MySql Database.
        :param table_name: Name of the table
        :param concurrency: Number of tasks that are launched to read the data
        :param partitions_df: Optional data frame, that contains all possible partitions for all database tables
        :return: A Spark DataFrame with the table data
        """
        # todo: explain in the method doc the strategy to use when reading from a
        #  table in parallel
        if partitions_df:
            partition_column = self._get_partition_column_from_df(
                partitions_df, table_name
            )
        else:
            partition_column = self._get_partition_column_from_table(table_name)

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
                    "dbtable": table_name,
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
        Gets the results of a query in a MySql database.
        :param query: Query content
        :param table_name: Name of the table relevant to the query # TODO this param could be removed
        :return: A Spark DataFrame with the query results
        """
        df = self.spark_client.get_data_from_external_source(
            format="jdbc", options={**self.spark_common_options, "query": query}
        )

        return df

    @logger
    def get_table_schema(self, table_name):
        """
        Gets the schema of a table in a MySql database.
        :param table_name: Name of a table
        :return: A Spark DataFrame with the table schema
        """
        query = """
            select
                COLUMN_NAME as col_name,
                COLUMN_TYPE as col_type
            FROM
                INFORMATION_SCHEMA.COLUMNS
            WHERE
                TABLE_NAME = '{table}'
            """.format(
            table=table_name
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
                k.TABLE_NAME,
                k.COLUMN_NAME,
                k.CONSTRAINT_NAME,
                s.`CARDINALITY`
            FROM
                information_schema.table_constraints t
                JOIN information_schema.key_column_usage k
                on t.constraint_name = k.constraint_name and t.table_schema =
                k.table_schema and t.table_name = k.table_name
                left JOIN information_schema.STATISTICS s
                on s.TABLE_NAME = t.TABLE_NAME and s.COLUMN_NAME = k.COLUMN_NAME
                join information_schema.COLUMNS c
                on c.TABLE_SCHEMA = t.TABLE_SCHEMA
                and c.TABLE_NAME = t.TABLE_NAME
                and c.COLUMN_NAME = k.COLUMN_NAME
            WHERE
                s.INDEX_NAME = 'PRIMARY'
                AND t.constraint_type='PRIMARY KEY'
                AND c.DATA_TYPE IN ('int', 'bigint', 'date', 'datetime', 'timestamp')
                AND t.table_schema='{db}'
                AND t.table_name = '{table}'
            GROUP by
                k.TABLE_NAME,
                k.CONSTRAINT_NAME,
                s.`CARDINALITY`
            ORDER by s.`CARDINALITY` desc
            """.format(
            db=self.conn_config["db"], table=table_name
        )
        df = self.get_data_from_query(query).select("COLUMN_NAME")

        if df.count():
            return df.collect()[0][0]

        logger.warning(
            "m=_get_partition_column_from_table, table={}, msg=Partition column "
            "to parallelize the table read was not found.".format(table_name)
        )

    def get_partition_columns_from_all_tables(self):
        """
        Tries to find good partition columns (a col with high cardinality) for all database tables.
        :return: Dataframe with columns with higher cardinality for each database table.
        """
        query = """
            SELECT
                k.TABLE_NAME as table_name,
                k.COLUMN_NAME as column_name,
                k.CONSTRAINT_NAME,
                s.`CARDINALITY` as cadinality
            FROM
                information_schema.table_constraints t
            JOIN
                information_schema.key_column_usage k
                    ON t.constraint_name = k.constraint_name
                    AND t.table_schema = k.table_schema
                    AND t.table_name = k.table_name
            LEFT JOIN
                information_schema.STATISTICS s
                    ON s.TABLE_NAME = t.TABLE_NAME
                    AND s.COLUMN_NAME = k.COLUMN_NAME
            JOIN
                information_schema.COLUMNS c
                    ON c.TABLE_SCHEMA = t.TABLE_SCHEMA
                    AND c.TABLE_NAME = t.TABLE_NAME
                    AND c.COLUMN_NAME = k.COLUMN_NAME
            WHERE
                s.INDEX_NAME = 'PRIMARY'
                AND t.constraint_type='PRIMARY KEY'
                AND c.DATA_TYPE IN ('int', 'bigint', 'date', 'datetime', 'timestamp')
                AND t.table_schema='{db}'
            GROUP by
                k.TABLE_NAME,
                k.CONSTRAINT_NAME,
                s.`CARDINALITY`
            ORDER by k.TABLE_NAME desc
            """.format(
            db=self.conn_config["db"]
        )
        df = self.get_data_from_query(query).select(
            "table_name", "column_name", "cadinality"
        )

        if not df.rdd.isEmpty():
            return df

        logger.warning(
            "m=get_partition_columns_from_all_tables, table={}, msg=Could not fetch "
            "partition columns for all tables."
        )

    @logger
    def get_incremental_data_from_table(
        self, table_name, date_filter_column, date_filter_value, unixtime_measure=None
    ):
        """
        Gets incremental data from table in a MySQL database.
        The method expects a table and a date/timestamp or unix timestamp
        column to make the filter.
        :param table_name: Name of the table
        :param date_filter_column: Name of the column to make the filter
        :param date_filter_value: Value of the column
        :param unixtime_measure: Unix time measure to be set as milliseconds or seconds
        :return: A Spark DataFrame with the table data
        """

        dt_filter_value = datetime.strptime(date_filter_value, "%Y-%m-%d")
        dt_filter_value_day_after = dt_filter_value + timedelta(days=1)

        if unixtime_measure == "milliseconds":
            filter_value = 1000 * int(dt_filter_value.timestamp())
            filter_value_day_after = 1000 * int(dt_filter_value_day_after.timestamp())

        elif unixtime_measure == "seconds":
            filter_value = int(dt_filter_value.timestamp())
            filter_value_day_after = int(dt_filter_value_day_after.timestamp())

        else:
            filter_value = f"'{dt_filter_value}'"
            filter_value_day_after = f"'{dt_filter_value_day_after}'"

        filter_condition = f"""{date_filter_column} >= {filter_value}
                                AND {date_filter_column} < {filter_value_day_after}
                                """

        query = f"""
                SELECT
                    *,
                    CAST({dt_filter_value.year} AS UNSIGNED) AS year,
                    CAST({dt_filter_value.month} AS UNSIGNED) AS month,
                    CAST({dt_filter_value.day} AS UNSIGNED) AS day
                FROM
                    {table_name}
                WHERE
                    {filter_condition}
                    """

        return self.get_data_from_query(query)
