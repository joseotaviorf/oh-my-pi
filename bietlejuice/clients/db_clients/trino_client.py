import trino
from quintoandar_logger import QuintoAndarLogger
from trino import constants
from trino.exceptions import TrinoUserError

from bietlejuice.clients.db_clients.db_client import DBClient

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

    def register_table(
        self,
        schema_name: str,
        table_name: str,
        table_location: str,
        throw_if_already_exists: bool = False,
    ) -> None:
        """
        Registers a table in Trino. Particularly useful for Delta Lake tables.

        :param schema_name: the schema name of the table
        :type schema_name: str
        :param table_name: the table name
        :type table_name: str
        :param table_location: the table location in the file system
        :type table_location: str
        :param throw_if_already_exists: if True, raises an exception if the table
            already exists
        :type throw_if_already_exists: bool
        """
        try:
            self.run(
                f"""
            CALL {self.conn.catalog}.system.register_table(
                schema_name => '{schema_name}',
                table_name => '{table_name}',
                table_location => '{table_location}'
            )
            """
            )
        except TrinoUserError as e:
            if e.error_name != "ALREADY_EXISTS" or throw_if_already_exists:
                raise e

    def unregister_table(
        self, schema_name: str, table_name: str, throw_if_not_exists: bool = False
    ):
        """
        Unregisters a table from Trino. Particularly useful for Delta Lake tables.

        :param schema_name: the schema name of the table
        :type schema_name: str
        :param table_name: the table name
        :type table_name: str
        :param throw_if_not_exists: if True, raises an exception if the table
            does not exist
        :type throw_if_not_exists: bool
        """
        try:
            self.run(
                f"""
            CALL {self.conn.catalog}.system.unregister_table(
                schema_name => '{schema_name}',
                table_name => '{table_name}'
            )
            """
            )
        except TrinoUserError as e:
            if e.error_name != "NOT_FOUND" or throw_if_not_exists:
                raise e

    def drop_table(self, schema_name: str, table_name: str):
        """
        Drops a table from Trino.

        :param schema_name: the schema name of the table
        :type schema_name: str
        :param table_name: the table name
        :type table_name: str
        """
        self.run(f'DROP TABLE "{schema_name}"."{table_name}"')

    def table_exists(self, schema_name: str, table_name: str) -> bool:
        """
        Checks if a table exists in Trino.

        :param schema_name: the schema name of the table
        :type schema_name: str
        :param table_name: the table name
        :type table_name: str
        :return: True if the table exists, False otherwise
        :rtype: bool
        """
        return bool(
            self.get_records(f"SHOW TABLES FROM {schema_name} LIKE '{table_name}'")
        )

    def get_table_ddl(self, schema_name: str, table_name: str) -> str:
        """
        Retrieves the DDL of a table in Trino.

        :param schema_name: the schema name of the table
        :type schema_name: str
        :param table_name: the table name
        :type table_name: str
        :return: the DDL of the table
        :rtype: str
        """
        return self.get_records(f'SHOW CREATE TABLE "{schema_name}"."{table_name}"')[0][
            0
        ]
