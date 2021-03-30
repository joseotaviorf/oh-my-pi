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
    def drop_table(self, dw_schema, table_name, if_exists=False):
        drop_table_sql = (
            f"DROP TABLE {'IF EXISTS' if if_exists else ''} {dw_schema}.{table_name}"
        )
        with closing(self.conn) as conn:
            with closing(conn.cursor()) as cur:
                cur.execute(drop_table_sql)
                conn.commit()

        logger.info("m=drop_table, msg=query execution succeeded")

    @logger
    def create_table_from_select(self, dw_schema, table_name, query):
        create_table_query = f"""
            CREATE TABLE {dw_schema}.{table_name}
            AS
            {query}
        """

        with closing(self.conn) as conn:
            with closing(conn.cursor()) as cur:
                cur.execute(create_table_query)
                conn.commit()

        logger.info("m=create_table_from_select, msg=query execution succeeded")

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
