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

    def __init__(
        self,
        host: str,
        port: int,
        user: str,
        password: str,
        catalog: str = "hive",
        **conn_params: dict,
    ):
        """
        :param host: the server host address
        :param port: server host port
        :param catalog: metastore catalog to connect in. Hive is set as default
        :param conn_params: The parameters can be found in trino.dbapi.Connection
        """
        params = {
            "host": host,
            "port": port,
            "user": user,
            "auth": trino.auth.BasicAuthentication(user, password),
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
    def get_records(self, query: str, parameters=None):
        """
        Executes a query in Trino and returns the result.

        :param query: query to be run
        :param parameters: query parameter values
        :type parameters: list or tuple
        :return: query result set
        :rtype: List[List[Any]]
        """
        with self.conn as conn:
            cur = conn.cursor()
            cur.execute(query, parameters)
            result = cur.fetchall()
            logger.info(
                f"m=get_records, records_returned={len(result)}, msg=Query "
                "execution succeeded."
            )
            return result

    @logger
    def run(self, command: str, parameters=None) -> None:
        """
        Executes a command in Trino without returning results.

        :param command: the command to be run
        :param parameters: query parameter values
        :type parameters: list or tuple
        """
        with self.conn as conn:
            cur = conn.cursor()
            cur.execute(command, parameters)
