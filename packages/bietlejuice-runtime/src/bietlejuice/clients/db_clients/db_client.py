from abc import ABC, abstractmethod


class DBClient(ABC):
    """
    Abstract base class for database clients.
    """

    @property
    @abstractmethod
    def conn(self):
        """
        Returns a connection object
        """
        pass

    @abstractmethod
    def get_records(self, query, parameters=None):
        """
        Executes a query and returns a set of records.

        :param query: the query statement to be executed
        :type query: str
        :param parameters: The parameters to render the SQL query with.
        :type parameters: mapping or iterable
        """
        pass

    @abstractmethod
    def run(self, command, autocommit=False, parameters=None):
        """
        Runs a command.

        :param command: the statement to be executed
        :type command: str
        :param autocommit: What to set the connection's autocommit setting to before
        executing the query.
        :type autocommit: bool
        :param parameters: The parameters to render the SQL query with.
        :type parameters: mapping or iterable
        """
        # todo: check this method signature and extend it to run multiples
        #  commands while committing only at the end of all. There are several
        #  approaches to achieve this goal: (1) allowing to receive a list instead of a
        #  single command in the command parameter, (2) adding a commit method to
        #  this interface (or to the interested children: e.g., PostgresClient) and
        #  setting autocommit param as True, among others.
        pass
