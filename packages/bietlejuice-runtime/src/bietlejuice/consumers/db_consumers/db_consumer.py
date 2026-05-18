from abc import ABC, abstractmethod

from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("DBConsumer")


class DBConsumer(ABC):
    """
    Abstract base class for database consumers.
    """

    @abstractmethod
    def get_table_names_and_sizes(self):
        """
        Gets the table names and sizes of a database.
        :return: A DataFrame with cols: table_name and size
        """
        pass

    @abstractmethod
    def get_data_from_table(self, table_name):
        """
        Gets all data from a table.
        :param table_name: Name of the table
        :return: A DataFrame with the table data
        """
        pass

    @abstractmethod
    def get_data_from_table_in_parallel(self, table_name, concurrency):
        """
        Gets all data from a table in parallel.
        :param table_name: Name of the table
        :param concurrency: Number of tasks that are launched to read the data
        :return: A DataFrame with the table data
        """
        pass

    @abstractmethod
    def get_incremental_data_from_table(self, table_name, column_name, execution_date):
        """
        Gets incremental data from a table based on a column of type date.
        :param table_name: Name of the table
        :param column_name:  Name of the column to be filtered
        :param execution_date: Value of the column to be filtered
        :return: A DataFrame with the table data
        """
        pass

    @abstractmethod
    def get_data_from_query(self, query, table_name=None):
        """
        Gets the results of a query.
        :param query: Query content
        :param table_name: Name of the table relevant to the query
        :return: A DataFrame with the query results
        """
        pass

    @abstractmethod
    def get_table_schema(self, table_name):
        """
        Gets the schema of a table.
        :param table_name: Name of a table
        :return: A DataFrame with the table schema
        """
        pass

    @logger
    def is_db_empty(self):
        """
        Checks if the database is empty.
        :return: True if empty, False otherwise.
        """
        try:
            result = self.get_table_names_and_sizes()
        except Exception as e:
            # todo: move the database existence check from this method to the children'
            #  constructors.
            raise RuntimeError(
                f"m=is_db_empty, msg=Database of this consumer does not exist., e={e}"
            )
        if result and result.count():
            return False

        return True
