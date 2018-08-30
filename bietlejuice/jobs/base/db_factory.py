import json
import os

import psycopg2
import psycopg2.extensions
import pymysql

from enum_db import EnumDbType


class DBFactory(object):
    """
    DB Factory
    Returns a connection of our DBs
    """

    @staticmethod
    def get_connection(db_enum, encoding, timeout=0):
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
            p = port if port else 5439 if dbtype == EnumDbType.Redshift else 5432
            conn = psycopg2.connect(host=host, user=user, password=pwd, database=db, port=p)
            print('port: {}'.format(p))
            if int(p) == 5432:
                print('setting client encoding to {}'.format(encoding))
                conn.set_client_encoding(encoding)

            if timeout:
                conn.cursor().execute("SET statement_timeout = '{}s'".format(timeout))

            return conn
        elif dbtype == EnumDbType.MySQL:
            conn = pymysql.connect(host, user, pwd, db)
            conn.set_charset(encoding)
            cur = conn.cursor()
            cur.execute('SET SQL_MODE=ANSI_QUOTES')
            return conn

        return None
