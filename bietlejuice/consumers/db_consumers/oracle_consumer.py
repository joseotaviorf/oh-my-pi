from datetime import datetime
import textwrap

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db.database_driver_enum import DatabaseDriverEnum
from bietlejuice.consumers.db_consumers.db_consumer import DBConsumer

logger = QuintoAndarLogger("OracleConsumer")


class OracleSparkConsumer(DBConsumer):
    """
    OracleSparkConsumer fetches data from an Oracle database via Spark
    and returns it as a Spark DataFrame.
    :param conn_config: A dict with the connection configuration values. It must
                        contain the keys: host, port, dbtype, service_name, user, pwd, and schema.
    :type conn_config: dict
    :param spark_client: A client to handle the Spark connection
    :type spark_client: SparkClient
    """

    def __init__(self, conn_config: dict, spark_client, fetch_size=50000):
        dbtype = conn_config["dbtype"]
        driver_enum = DatabaseDriverEnum[dbtype.upper()]
        self.conn_config = conn_config
        self.schema = self.conn_config["schema"]
        self.spark_client = spark_client
        self.spark_common_options = {
            "driver": driver_enum.value,
            "url": "jdbc:oracle:thin:@{}:{}/{}".format(
                self.conn_config["host"],
                self.conn_config["port"],
                self.conn_config["service_name"],
            ),
            "user": self.conn_config["user"],
            "password": self.conn_config["pwd"],
            "fetchsize": fetch_size,
        }

    @logger
    def get_data_from_query(self, query: str, table_name: str = None):
        """
        Executes a query against the Oracle database.

        :param query: SQL query to execute.
        :type query: str
        :param table_name: Optional name of the table relevant to the query, for logging purposes.
        :type table_name: str, optional
        :return: A Spark DataFrame with the query results.
        """

        logger.info(f"Executing query: {query}")
        return self.spark_client.get_data_from_external_source(
            format="jdbc", options={**self.spark_common_options, "query": query}
        )

    @logger
    def get_data_from_table(self, table_name: str):
        """
        Fetches all data from a specified table.

        :param table_name: Name of the table.
        :type table_name: str
        :return: A Spark DataFrame with the table data.
        """

        extended_table_name = f"{self.schema}.{table_name}"
        logger.info(f"Fetching data from table: {extended_table_name}")

        return self.spark_client.get_data_from_external_source(
            format="jdbc",
            options={**self.spark_common_options, "dbtable": extended_table_name},
        )

    @logger
    def get_table_names_and_sizes(self, table_name: str):
        """
        Retrieves the names and sizes of tables in the Oracle database.

        :param table_name: Name of the table to retrieve.
        :type table_name: str
        :return: A Spark DataFrame with columns: table_name and size (estimated size in MB).
        """

        query = f"""
            SELECT
                TABLE_NAME,
                ROUND(NUM_ROWS*(AVG_ROW_LEN/1024/1024),2) size
            FROM all_tables
            WHERE OWNER = '{self.schema}'
            AND TABLE_NAME = '{table_name}'
        """

        return self.get_data_from_query(query)

    @logger
    def get_data_from_table_in_parallel(self, table_name: str, concurrency: int):
        """
        Fetches data from a table in parallel using multiple tasks.

        :param table_name: Name of the table.
        :type table_name: str
        :param concurrency: Number of parallel tasks to launch.
        :type concurrency: int
        :return: A Spark DataFrame with the table data.
        """

        partition_columns_df = self.get_partition_column_from_table(table_name)
        if not partition_columns_df:
            logger.warning(f"No partition column found for table {table_name}.")
            return self.get_data_from_table(table_name)

        partition_column = partition_columns_df.collect()[0][0]
        logger.info(f"Partition column: {partition_column}")

        query = f"SELECT MIN({partition_column}),MAX({partition_column}) FROM {self.schema}.{table_name}"
        bounds_df = self.get_data_from_query(query)
        lower_bound, upper_bound = bounds_df.collect()[0]

        logger.info(
            f"Table {table_name} has upper_bound and lower_bound {upper_bound - lower_bound} for partition {partition_column}"
        )

        return self.spark_client.get_data_from_external_source(
            format="jdbc",
            options={
                **self.spark_common_options,
                "dbtable": f"{self.schema}.{table_name}",
                "partitionColumn": partition_column,
                "lowerBound": int(lower_bound),
                "upperBound": int(upper_bound),
                "numPartitions": concurrency,
            },
        )

    @logger
    def get_table_schema(self, table_name: str):
        """
        Retrieves the schema of a specified table.

        :param table_name: Name of the table.
        :type table_name: str
        :return: A Spark DataFrame with the table schema.
        """

        query = f"""
            SELECT
                column_name,
                data_type,
                data_length,
                data_precision,
                data_scale,
                identity_column,
                char_length,
                nullable,
                num_nulls,
                num_distinct,
                high_value,
                low_value,
                last_analyzed
            FROM
                all_tab_columns
            WHERE
                owner =  '{self.schema}'
                AND table_name = '{table_name}'
        """

        return self.get_data_from_query(textwrap.dedent(query))

    @logger
    def get_table_primary_keys(self, table_name: str):
        """
        Retrieves the primary keys of a specified table.

        :param table_name: Name of the table.
        :type table_name: str
        :return: A Spark DataFrame with the table's primary keys.
        """

        query = f"""
        SELECT
            cons.constraint_name,
            cons.constraint_type,
            cons.table_name,
            cols.column_name,
            cons.r_constraint_name
        FROM
            all_constraints cons
            LEFT JOIN all_cons_columns cols ON cons.constraint_name = cols.constraint_name
        WHERE
            cons.owner = '{self.schema}'
            AND cons.table_name = '{table_name}'
            AND cons.constraint_type IN ('U', 'P', 'R')
        """

        return self.get_data_from_query(textwrap.dedent(query))

    @logger
    def get_partition_column_from_table(self, table_name: str):
        """
        Identifies a suitable partition column from a specified table.

        :param table_name: Name of the table.
        :type table_name: str
        :return: A Spark DataFrame with the table partition column.
        """

        query = f"""
            SELECT
                column_name
            FROM
                all_part_key_columns
            WHERE
                owner = '{self.schema}'
                AND name = '{table_name}'
        """

        return self.get_data_from_query(textwrap.dedent(query))

    @logger
    def get_incremental_data_from_table(
        self,
        table_name: str,
        date_filter_columns: list,
        start_interval: str,
        end_interval: str,
        unixtime_measure: str = None,
    ):
        """
        Fetches incremental data from a table based on a date filter.

        :param table_name: Name of the table.
        :type table_name: str
        :param date_filter_column: Column name to apply the date filter on.
        :type date_filter_column: str
        :param date_filter_value: Date value to filter records from (YYYY-MM-DD format).
        :type date_filter_value: str
        :param unixtime_measure: Indicate whether the date filter is in 'seconds' or 'milliseconds'. Defaults to None.
        :type unixtime_measure: str, optional
        :return: A Spark DataFrame with the filtered table data.
        """

        dt_start_filter = datetime.strptime(start_interval, "%Y-%m-%d")
        dt_end_filter = datetime.strptime(end_interval, "%Y-%m-%d")

        if unixtime_measure == "milliseconds":
            start_range_date = 1000 * int(dt_start_filter.timestamp())
            end_range_date = 1000 * int(dt_end_filter.timestamp())
        elif unixtime_measure == "seconds":
            start_range_date = int(dt_start_filter.timestamp())
            end_range_date = int(dt_end_filter.timestamp())
        else:
            start_range_date = dt_start_filter
            end_range_date = dt_end_filter

        if len(date_filter_columns) > 1:
            date_filters = ", \n".join(
                f"NVL({date_filter}, TO_DATE('1970-01-01', 'YYYY-MM-DD'))"
                for date_filter in date_filter_columns
            )
            fields_filter = f"TRUNC(GREATEST({date_filters}))"

        else:
            fields_filter = ", ".join(
                date_filter for date_filter in date_filter_columns
            )

        filters = f"""
                {fields_filter}
                BETWEEN TO_DATE('{start_range_date}', 'YYYY-MM-DD HH24:MI:SS')
                AND TO_DATE('{end_range_date}', 'YYYY-MM-DD HH24:MI:SS')
            """

        query = f"""
            SELECT *
            FROM {self.schema}.{table_name}
            WHERE {filters}
        """

        return self.get_data_from_query(query)

    @logger
    def get_table_modifications(self, table_name: str):
        """
        Retrieves modifications made to a specified table.

        :param table_name: Name of the table.
        :type table_name: str
        :return: A Spark DataFrame with columns: table_name, partition_name, subpartition_name, inserts, updates, deletes, timestamp, truncated, drop_segments.
        """

        query = f"""
        SELECT
            TABLE_NAME,
            PARTITION_NAME,
            SUBPARTITION_NAME,
            INSERTS,
            UPDATES,
            DELETES,
            TIMESTAMP,
            TRUNCATED,
            DROP_SEGMENTS
        FROM ALL_TAB_MODIFICATIONS
        WHERE TABLE_OWNER = '{self.schema}'
        AND TABLE_NAME = '{table_name}'
        ORDER BY TIMESTAMP DESC
        """

        return self.get_data_from_query(query)
