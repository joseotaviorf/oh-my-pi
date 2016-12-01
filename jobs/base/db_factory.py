import os
import json
import pymysql
import psycopg2
import psycopg2.extensions
from enum_db import EnumDb, EnumDbType


class DBFactory(object):
    """
    DB Factory
    Returns a connection of our DBs
    """

    @staticmethod
    def get_connection(db_enum):
        env_str = os.environ.get(str(db_enum))
        env = json.loads(env_str)

        host = env['host']
        user = env['user']
        pwd = env['pwd']
        db = env['db']
        dbtype = env['dbtype']
        port = env.get('port')

        if dbtype == EnumDbType.PostgreSQL or dbtype == EnumDbType.Redshift:
            psycopg2.extensions.register_type(psycopg2.extensions.UNICODE)
            psycopg2.extensions.register_type(psycopg2.extensions.UNICODEARRAY)
            default_port = port if port else 5439 if dbtype==EnumDbType.Redshift else 5432
            conn = psycopg2.connect(host=host, user=user, password=pwd, database=db, port=default_port)
            conn.set_client_encoding('LATIN1')
            return conn
        elif dbtype == EnumDbType.MySQL:
            conn = pymysql.connect(host, user, pwd, db)
            cur = conn.cursor()
            cur.execute('SET SQL_MODE=ANSI_QUOTES')
            return conn

        return None
