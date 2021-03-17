import trino
from quintoandar_logger import QuintoAndarLogger
from trino import constants

from bietlejuice.jobs.composer.clients.db_clients.db_client import DBClient

logger = QuintoAndarLogger("TrinoClient")


class TrinoClient(DBClient):
    """
    Client to keep the interface standards defined in DBClient for database
     clients. This client interacts with Trino server for running commands
     and returning query results.
    """

    def __init__(self, host, port, user, catalog="hive", **conn_params):
        """
        :param host: the server host address
        :type host: str
        :param port: server host port
        :type port: int
        :param user: the username
        :type user: str
        :param catalog: metastore catalog to connect in. Hive is set as default
        :type catalog: str
        :param conn_params: The parameters can be found in trino.dbapi.Connection
        :type conn_params: dict
        """
        params = {
            "host": host,
            "port": port,
            "user": user,
            "catalog": catalog,
            "http_scheme": constants.HTTPS,
        }

        conn_params.update(params)
        self.connection = trino.dbapi.connect(**conn_params)

    @property
    def conn(self):
        """
        :return: Connection object.
        """
        return self.connection

    @logger
    def get_records(self, query, parameters=None):
        """
        Executes a query in Trino and returns the result.

        :param query: query to be run
        :type query: str
        :param parameters: query parameter values
        :type parameters: list or tuple
        :return: query result set
        :rtype: List[List[Any]]
        """
        with self.conn as conn:
            cur = conn.cursor()
            cur.execute(query, parameters)
            logger.info(
                f"m=get_records, records_returned={cur.rowcount}, msg=Query "
                "execution succeeded."
            )
            return cur.fetchall()

    @logger
    def run(self, command, parameters=None):
        """
        Executes a command in Trino without returning results.

        :param command: the command to be run
        :type command: str
        :param parameters: query parameter values
        :type parameters: list or tuple
        :return: None
        """
        with self.conn as conn:
            cur = conn.cursor()
            cur.execute(command, parameters)
