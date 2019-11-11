from contextlib import closing

import psycopg2
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.clients.db_clients.db_client import DBClient

logger = QuintoAndarLogger("PostgresClient")


class PostgresClient(DBClient):
    """
    Run commands and return query results in Postgres.
    You can specify ssl parameters as ``"sslmode": "require", "sslcert":
    "/path/to/cert.pem", etc``.

    Note: For Redshift, use keepalives_idle in the connection parameters
    and set it to less than 300 seconds.
    """

    def __init__(self, **conn_params):
        self.conn_params = conn_params

    @property
    def conn(self):
        """
        Returns a connection object.
        It's recommended to use this method altogether with contextlib.closing to
        ensure closing the connection at the end.
        """
        return psycopg2.connect(**self.conn_params)

    @logger
    def get_records(self, query, parameters=None):
        with closing(self.conn) as conn:
            with closing(conn.cursor()) as cur:
                if parameters is not None:
                    cur.execute(query, parameters)
                else:
                    cur.execute(query)
                logger.info(
                    "m=get_records, nb_records={}, msg=query execution "
                    "succeeded".format(cur.rowcount)
                )
                return cur.fetchall()

    @logger
    def run(self, command, autocommit=False, parameters=None):
        with closing(self.conn) as conn:
            conn.autocommit = autocommit
            with closing(conn.cursor()) as cur:
                if parameters is not None:
                    cur.execute(command, parameters)
                else:
                    cur.execute(command)

            # If autocommit was set to False, we do a manual commit.
            if not autocommit:
                conn.commit()
