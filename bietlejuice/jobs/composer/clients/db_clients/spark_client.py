from pyspark.sql import SparkSession
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.clients.db_clients.db_client import DBClient

logger = QuintoAndarLogger("SparkSqlClient")


class SparkClient(DBClient):
    """
    Run commands, return query results and reads data from external systems with Spark.
    """

    def __init__(self, session_params=None):
        self._session = None
        self.session_params = session_params

    @property
    def conn(self):
        """
        Gets or creates an SparkSession
        :return: SparkSession
        """
        if not self._session:
            session_builder = SparkSession.builder
            if self.session_params:
                for param, val in self.session_params.items():
                    session_builder.config(param, val)
            self._session = session_builder.getOrCreate()
        return self._session

    @logger
    def get_records(self, query, parameters=None):
        # todo: check if the session needs to be closed at the end. Right now,
        #  the session is never closed explicitly.
        df = self.conn.sql(query)

        return df

    @logger
    def run(self, command, autocommit=False, parameters=None):
        # todo: check if the session needs to be closed at the end. Right now,
        #  the session is never closed explicitly.
        self.conn.sql(command)

    @logger
    def get_data_from_external_source(self, format, options, path=None):
        """
        Gets data from an external source with spark.
        :param format: The format of the connection (e.g. jdbc, mongo)
        :param options: Spark options to read the data (e.g. url, user, pwd)
        :param path: optional string or a list of string for file-system backed data sources.
        :return: A Spark DataFrame
        """
        if not isinstance(format, str):
            raise ValueError("format needs to be a string with the desired read format")
        if not isinstance(options, dict):
            raise ValueError("options needs to be a dict with the setup configurations")
        # todo: check if the session needs to be closed at the end. Right now,
        #  the session is never closed explicitly.
        return self.conn.read.format(format).options(**options).load(path=path)

    @logger(exclude="data")
    def create_dataframe(
        self, data, schema=None, sampling_ratio=None, verify_schema=True
    ):
        """
        Creates a DataFrame from an RDD, a list or a pandas.DataFrame. This method is
        a wrapper to the spark.createDataFrame method. In case of doubt, check the
        docs of the wrapped method.
        :param data: an RDD of any kind of SQL data representation(e.g. row, tuple,
        int, boolean, etc.), or list, or pandas.DataFrame.
        :param schema:  a pyspark.sql.types.DataType or a datatype string or a list
        of column names, default is None. The data type string format equals to
        pyspark.sql.types.DataType.simpleString, except that top level struct type
        can omit the struct<> and atomic types use typeName() as their format,
        e.g. use byte instead of tinyint for
        :param sampling_ratio: the sample ratio of rows used for inferring
        :param verify_schema: verify data types of every row against schema
        :return: A Spark DataFrame
        """
        df = self.conn.createDataFrame(data, schema, sampling_ratio, verify_schema)

        return df
