from pyspark.sql import SparkSession
from python_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.consumers.consumer import Consumer

logger = QuintoAndarLogger('MySQLConsumer')


class MySQLConsumer(Consumer):

    def __init__(self, db_enum):
        connection = self.get_connection(db_enum)
        if self.connection['dbtype'] != 'mysql':
            raise RuntimeError(
                'm=__init__, msg={} connection is not a mysql connection ({})'.format(db_enum,
                                                                                      self.connection[
                                                                                          'dbtype']))

        connection['url'] = "jdbc:mysql://{}:{}/{}".format(connection['host'],
                                                           connection['port'],
                                                           connection['db'])
        connection['driver'] = 'com.mysql.jdbc.Driver'
        self.connection = connection

    @logger
    def _get_default_read_format_and_options(self):
        spark = SparkSession.builder.getOrCreate()

        return spark.read.format('jdbc') \
            .option("fetchsize", 500000) \
            .option("driver", self.connection['driver']) \
            .option("url", self.connection['url']) \
            .option("user", self.connection['user']) \
            .option("password", self.connection['pwd'])

    def get_table_names_and_sizes(self):
        query = """
    SELECT
      table_name AS `table`,
      round(((data_length + index_length) / 1024 / 1024), 2) AS `size`
    FROM
      information_schema.TABLES
    where
      table_schema = '{db}'
    ORDER BY
      (data_length + index_length) DESC
    """
        result = self.get_data_from_query(query.format(db=self.connection['db']))

        return result

    def get_data_from_table(self, table):
        remote_table = self._get_default_read_format_and_options() \
            .option("dbtable", table) \
            .load()

        return remote_table

    def _get_partition_column_from_table(self, table):
        query = """
    SELECT
        k.TABLE_NAME,
        k.COLUMN_NAME,
        k.CONSTRAINT_NAME,
        s.`CARDINALITY`
    FROM
        information_schema.table_constraints t
        JOIN information_schema.key_column_usage k
        on t.constraint_name = k.constraint_name and t.table_schema = k.table_schema and t.table_name = k.table_name
        left JOIN information_schema.STATISTICS s
        on s.TABLE_NAME = t.TABLE_NAME and s.COLUMN_NAME = k.COLUMN_NAME
    WHERE
        s.INDEX_NAME = 'PRIMARY'
        AND t.constraint_type='PRIMARY KEY'
        AND t.table_schema='{db}'
        AND t.table_name = '{table}'
    GROUP by
        k.TABLE_NAME,
        k.CONSTRAINT_NAME,
        s.`CARDINALITY`
    ORDER by s.`CARDINALITY` desc
    """
        df = self.get_data_from_query(query.format(db=self.connection['db'], table=table)) \
            .select('COLUMN_NAME')

        if not len(df.head(1)):
            column = ''
        else:
            column = df.collect()[0][0]

        return column

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

            remote_table = remote_table \
                .option("partitionColumn", partition_column) \
                .option("lowerBound", lower_bound) \
                .option("upperBound", upper_bound)
        else:
            logger.warning(
                'm=get_data_from_table_in_parallel, msg=Partition column to parallelize the table extraction'
                'was not found, getting the data serially.')

        remote_table = remote_table \
            .option("dbtable", table) \
            .option("numPartitions", concurrency) \
            .load()

        return remote_table

    def get_data_from_query(self, query):
        remote_table = self._get_default_read_format_and_options() \
            .option("query", query) \
            .load()
        return remote_table

    def get_table_schema(self, table):
        raise NotImplementedError()
