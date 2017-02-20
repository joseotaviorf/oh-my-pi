from logging import info as log
from enum_db import EnumDb, EnumDbType
import boto3
from db_factory import DBFactory
import zipfile
import gzip
import re
import io
import petl
import json
import os
import datetime
import sys
from decimal import Decimal
import codecs
import ast


class BaseETL(object):

    def __init__(self, *args, **kwargs):
        pass

    @staticmethod
    def now():
        return datetime.datetime.utcnow()

    @classmethod
    def decode_table(cls, table, encoding):
        table_r = []

        for line in table:
            line_r = []
            for i in line:
                if type(i) is str or type(i) is unicode:
                    i = i.decode(encoding)
                line_r.append(i)
            table_r.append(line_r)
        return table_r

    @staticmethod
    def get_json_from_zipfile(f):
        messages = []
        with zipfile.ZipFile(f, 'r') as zfile:
            for name in zfile.namelist():
                if re.search(r'\.gz$', name):
                    buffer_gz = io.BytesIO(zfile.read(name))
                    with gzip.GzipFile(fileobj=buffer_gz, mode='rb') as gzfile:
                        file_content = gzfile.read()
                        for x in file_content[0:-1].split('\n'):
                            yield json.dumps(json.loads(x))
                        #messages += [json.dumps(json.loads(x)) for x in file_content[0:-1].split('\n')]
        #return messages

    @staticmethod
    def get_table_from_json_child(events, json_column_name, attrib_name, value):
        events[json_column_name][value][attrib_name] = value
        return petl.fromdicts([events[json_column_name][value]])

    @staticmethod
    def publish_messages(messages, queue_name):
        sqs = boto3.resource('sqs')
        queue = sqs.get_queue_by_name(QueueName=queue_name)
        for message in messages:
            queue.send_message(
                MessageBody=message
            )

    @staticmethod
    def publish_notifications(notifications, topic_arn):
        sns = boto3.client('sns')
        c = 0
        for n in notifications:
            sns.publish(
                TopicArn=topic_arn,
                Message=n
            )
            c+=1
        return c

    @classmethod
    def json_loads_byteified(cls, json_text):
        return cls._byteify(
            json.loads(json_text, object_hook=cls._byteify),
            ignore_dicts=True
        )

    @classmethod
    def _byteify(cls, data, ignore_dicts=False):
        # if this is a unicode string, return its string representation
        if isinstance(data, unicode):
            return data.encode('utf-8')
        # if this is a list of values, return list of byteified values
        if isinstance(data, list):
            return [cls._byteify(item, ignore_dicts=True) for item in data]
        # if this is a dictionary, return dictionary of byteified keys and values
        # but only if we haven't already byteified it
        if isinstance(data, dict) and not ignore_dicts:
            return {
                cls._byteify(key, ignore_dicts=True): cls._byteify(value, ignore_dicts=True)
                for key, value in data.iteritems()
                }
        # if it's anything else, return it in its original form
        return data

    @classmethod
    def get_message_content(cls, message):
        body = json.loads(message.body)
        # m = json.loads(body[u'Message']) if body.get(u'Message') else body
        # m = ast.literal_eval(json.dumps(body[u'Message'])) if body.get(u'Message') else body
        # m = body[u'Message'] if body.get(u'Message') else body
        m = cls.json_loads_byteified(body[u'Message'] if body.get(u'Message') else body)
        m = json.dumps(m)
        return m

    @staticmethod
    def get_connection(db_enum, encoding='LATIN1'):
        return DBFactory.get_connection(db_enum, encoding)

    @classmethod
    def to_db(cls, db_enum, data_table, table_name,
              encoding='LATIN1', append=True, schema=None, commit=True, conn=None, create=False):
        """table: list of lists like a PETL Table """
        if not conn:
            conn = cls.get_connection(db_enum=db_enum, encoding=encoding)

        log('Loading {} on {} - Number of rows:{}. {}'.format(
            table_name, db_enum, len(data_table), datetime.datetime.now())
        )
        if append and not create:
            petl.appenddb(table=data_table, dbo=conn, tablename=table_name, schema=schema, commit=commit)
        else:
            petl.todb(table=data_table, dbo=conn, tablename=table_name, schema=schema, commit=commit, create=create)
        log('{} rows loaded on {}. {}'.format(len(data_table)-1, db_enum, datetime.datetime.now()))
        sys.stdout.flush()

    @staticmethod
    def format_parameters_to_db(line, encode_to='LATIN1'):
        l = []
        for item in line:
            if isinstance(item, datetime.datetime):
                if len(str(item)) <= 8:
                    l.append(datetime.datetime.strftime(item, "%Y%m%d"))
                else:
                    l.append(datetime.datetime.strftime(item, "%Y-%m-%d %H:%M:%S"))
            elif item is None:
                l.append('null')
            elif isinstance(item, Decimal):
                l.append(float(item))
            elif isinstance(item, unicode) or isinstance(item, str):
                l.append(item.encode(encode_to).replace("'", "").replace(",", ""))
            else:
                l.append(item)
        values = str(l).replace('[', '(').replace(']', ')').replace("'null'", "null")
        return values

    @staticmethod
    def format_parameter(p):
        return "'{0}'".format(str(p)) if p else 'null'

    @classmethod
    def execute_function(cls, db_enum, function_name, table=None, conn=None, encoding='LATIN1', commit=False):
        if not conn:
            conn = cls.get_connection(db_enum, encoding)

        conn.autocommit = commit
        if table:
            for line in table:
                if line != table[0]:
                    values = cls.format_parameters_to_db(line)
                    command = "select {0} {1}".replace("()", "").format(function_name, values)
                    conn.cursor().execute(command)
        else:
            fn = function_name if (str(function_name).strip().endswith(")")) else "{0}()".format(function_name)
            command = "select {0}".format(fn)
            conn.cursor().execute(command)

    @classmethod
    def execute_command(cls, command, db_enum=None, conn=None, encoding='LATIN1', commit=False, in_iterator=False):
        if not db_enum and not conn:
            raise AttributeError()
        if not conn:
            conn = cls.get_connection(db_enum, encoding)
        if not in_iterator:
            conn.autocommit = commit

        print ('Start Execute Command at: {}'.format(cls.now()))
        conn.cursor().execute(command)
        print ('End Execute Command at: {}'.format(cls.now()))

    @classmethod
    def insert_row(cls, table, db_enum, table_name, key_name=None, conn=None, encoding='LATIN1', commit=True):
        if not conn:
            conn = cls.get_connection(db_enum, encoding)

        conn.autocommit = commit
        header = cls.format_parameters_to_db(table[0]).replace("'", "\"")
        id_of_new_row = None
        for line in table:
            if line != table[0]:
                values =  cls.format_parameters_to_db(line)
                return_value = """returning "{}" """.format(key_name) if key_name is not None else ""
                command = """insert into {0}{1} values {2} {3};""".format(table_name, header, values, return_value)
                cursor = conn.cursor()
                cursor.execute(command)
                id_of_new_row = cursor.fetchone()[0]

        return id_of_new_row

    @staticmethod
    def update_data(table, db_enum, table_name, key_name=None, conn=None, commit=True):
        raise Exception("Not implemented")

    @classmethod
    def from_db_table(cls, db_enum, table_name, encoding='LATIN1', server_cursor_postgres=None, generator=False):
        return cls.from_db_query(db_enum=db_enum, query='SELECT * FROM {}'.format(table_name),
                                 encoding=encoding, server_cursor_postgres=server_cursor_postgres, generator=generator)

    @classmethod
    def from_db_query(cls, db_enum, query, encoding='LATIN1', server_cursor_postgres=None, conn=None, generator=False):
        if not conn:
            conn = cls.get_connection(db_enum, encoding)
        print('Starting {} on {}. {}'.format(query, db_enum, datetime.datetime.now()))

        l = None
        if server_cursor_postgres:
            l = petl.fromdb(lambda: conn.cursor(name=server_cursor_postgres), query)
            print('Server cursor created: {} - {}'.format(server_cursor_postgres, datetime.datetime.now()))
        else:
            ret = petl.fromdb(conn, query)
            if not generator:
                l = list(ret)
                print('Query returned {} rows. {}'.format(len(l), datetime.datetime.now()))
            else:
                l = ret
                print('Query returned a generator... - {}'.format(datetime.datetime.now()))
        sys.stdout.flush()
        return l

    @classmethod
    def get_table_count(cls, db_enum, table_name):
        return cls.from_db_query(
            query="select count(1) from {}".format(table_name),
            db_enum=db_enum
        )[1][0]

    @classmethod
    def table_exists(cls, db_enum, table_name):
        exists = cls.from_db_query(
            query="""
                SELECT 1
                FROM   information_schema.tables
                WHERE  table_schema = 'public'
                AND    table_name = '{}'
                """.format(table_name),
            db_enum=db_enum
        )
        return len(exists) > 1 and exists[1][0]


    @classmethod
    def drop_table(cls, db_enum, table_name, schema='public'):
        cls.execute_command(command='DROP TABLE IF EXISTS "{}"."{}";'.format(schema, table_name), db_enum=db_enum, commit=True)

    @classmethod
    def move_table(cls, table_name, enum_db_source, enum_db_dest,
                   table_name_dest=None, append=True, encoding='utf8', server_cursor_postgres=None):
        data_table = cls.from_db_table(db_enum=enum_db_source, table_name=table_name,
                                       encoding=encoding,server_cursor_postgres=server_cursor_postgres)
        if not table_name_dest:
            table_name_dest = table_name
        filename = '{}.csv'.format(table_name_dest)
        bucket_name = cls.to_s3(filename, data_table, encoding=encoding)
        cls.bulk_insert_from_s3(bucket_name, filename, enum_db_dest, table_name_dest, append, encoding)

        return bucket_name, filename

    @classmethod
    def bulk_insert_from_s3(cls, bucket_name, filename, enum_db_dest, table_name, append=True, encoding='LATIN1'):
        aws_access_key_id = os.environ.get('AWS_ACCESS_KEY_ID')
        aws_secret_access_key = os.environ.get('AWS_SECRET_ACCESS_KEY')
        con = cls.get_connection(enum_db_dest, encoding)
        sql = """COPY {} FROM '{}'
                    CREDENTIALS 'aws_access_key_id={};aws_secret_access_key={}'
                    DELIMITER '{}' FORMAT CSV IGNOREHEADER 1; commit;""".format(
            table_name,
            's3://{}/{}'.format(bucket_name, filename),
            aws_access_key_id,
            aws_secret_access_key,
            ',')
        try:
            if not append:
                con.cursor().execute('truncate table {};'.format(table_name))
            con.cursor().execute(sql)
        finally:
            con.close()
            cls.delete_file_s3(bucket_name, filename)

    @classmethod
    def bulk_insert(cls, table, table_name, db_enum,
                    encoding='LATIN1', append=True, commit=True, delimiter=','):
        csv_temp = '/tmp/{}.csv'.format(table_name)
        petl.tocsv(table=table, source=csv_temp, delimiter=delimiter, encoding=encoding)

        conn = BaseETL.get_connection(db_enum=db_enum, encoding=encoding)
        cur = conn.cursor()
        if not append:
            cur.execute('TRUNCATE TABLE {}'.format(table_name))
        # with open(csv_temp) as f:
        with codecs.open(filename=csv_temp, encoding=encoding) as f:
            # cur.copy_from(f, table_name, delimiter)
            sql = """COPY {} FROM stdin DELIMITER '{}' CSV header;""".format(table_name, delimiter)
            cur.copy_expert(sql, f)

        if commit:
            conn.commit()

    @classmethod
    def to_s3(cls, filename, data_table, encoding='utf8'):
        tmp_dir = '/tmp/'
        tmp_fn = tmp_dir + filename
        try:
            bucket_name = os.environ['s3-tmpfiles'] if os.environ.get('s3-tmpfiles') else 'bi-etl-ejuice-tmpfiles'
            petl.tocsv(data_table, tmp_fn, encoding=encoding)

            s3 = boto3.client('s3')
            s3.upload_file(tmp_fn, bucket_name, filename)
        except Exception as ex:
            log(ex)
            sys.stdout.flush()
            return None
        finally:
            os.remove(tmp_fn)

        return bucket_name

    @staticmethod
    def delete_file_s3(bucket_name, fn):
        s3 = boto3.resource('s3')
        bucket = s3.Bucket(bucket_name)
        bucket.delete_objects(
            Delete={
                'Objects': [
                    {
                        'Key': fn
                    }
                ]
            }
        )

    @classmethod
    def get_surrogate_key(cls, dimension_table, fact_table, dimension_key, fact_key, sk_name_column,
                          filter_injected_rule=None, rename_dict=None, remove_fact_key=False):
        table = petl.leftjoin(fact_table, dimension_table, lkey=fact_key, rkey=dimension_key, missing='-1')
        if filter_injected_rule:
            table = table.select(lambda item: filter_injected_rule(item))

        cutout_columns = list(dimension_table[0])
        cutout_columns.remove(dimension_key)
        cutout_columns.remove(sk_name_column)
        if remove_fact_key:
            cutout_columns.append(fact_key)

        table = table.cutout(*cutout_columns)

        if rename_dict:
            table = table.rename(rename_dict)

        return table
