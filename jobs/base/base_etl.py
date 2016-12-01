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
from decimal import Decimal


class BaseETL(object):

    def __init__(self, *args, **kwargs):
        pass

    @staticmethod
    def now():
        return datetime.datetime.utcnow()

    @staticmethod
    def get_json_from_zipfile(f):
        messages = []
        with zipfile.ZipFile(f, 'r') as zfile:
            for name in zfile.namelist():
                if re.search(r'\.gz$', name):
                    buffer_gz = io.BytesIO(zfile.read(name))
                    with gzip.GzipFile(fileobj=buffer_gz, mode='rb') as gzfile:
                        file_content = gzfile.read()
                        messages += [json.dumps(json.loads(x)) for x in file_content[0:-1].split('\n')]
        return messages

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
        for n in notifications:
            sns.publish(
                TopicArn=topic_arn,
                Message=n
            )

    @classmethod
    def get_message_content(cls, message):
        body = json.loads(message.body)
        m = json.loads(body['Message']) if body.get('Message') is not None else body
        return m

    @staticmethod
    def get_connection(db_enum):
        return DBFactory.get_connection(db_enum)

    @classmethod
    def to_db(cls, db_enum, data_table, table_name, append=True, schema=None, commit=True, conn=None, create=False):
        """table: list of lists like a PETL Table """
        if not conn:
            conn = cls.get_connection(db_enum=db_enum)

        print('Loading {} on {} - Number of rows:{}. {}'.format(table_name, db_enum, len(data_table), datetime.datetime.now()))
        if append:
            petl.appenddb(table=data_table, dbo=conn, tablename=table_name, schema=schema, commit=commit)
        else:
            petl.todb(table=data_table, dbo=conn, tablename=table_name, schema=schema, commit=commit, create=create)
        print('{} rows loaded on {}. {}'.format(len(data_table), db_enum), datetime.datetime.now())

    @staticmethod
    def format_parameters_to_db(line, encode_to='utf-8'):
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
    def execute_function(cls, db_enum, function_name, table=None, conn=None, commit=False):
        if not conn:
            conn = cls.get_connection(db_enum)

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
    def execute_command(cls, command, db_enum=None, conn=None, commit=False, in_iterator=False):
        if not db_enum and not conn:
            raise AttributeError()
        if not conn:
            conn = cls.get_connection(db_enum)
        if not in_iterator:
            conn.autocommit = commit
        conn.cursor().execute(command)

    @classmethod
    def insert_row(cls, table, db_enum, table_name, key_name=None, conn=None, commit=True):
        if not conn:
            conn = cls.get_connection(db_enum)

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
    def from_db_table(cls, db_enum, table_name):
        return cls.from_db_query(db_enum=db_enum, query='SELECT * FROM {}'.format(table_name))

    @classmethod
    def from_db_query(cls, db_enum, query):
        conn = cls.get_connection(db_enum)
        print('Starting {} on {}. {}'.format(query, db_enum, datetime.datetime.now()))
        l = list(petl.fromdb(conn, query))
        print('Query returned {} rows. {}'.format(len(l), datetime.datetime.now()))
        return l

    @classmethod
    def from_s3(cls, db_enum, query):
        conn = cls.get_connection(db_enum)
        return list(petl.fromdb(conn, query))

    @classmethod
    def move_table(cls, table_name, enum_db_source, enum_db_dest):
        data_table = cls.from_db_table(db_enum=enum_db_source, table_name=table_name)
        filename = '{}.csv'.format(table_name)
        bucket_name = cls.to_s3(filename, data_table)
        cls.bulk_insert_from_s3(bucket_name, filename, enum_db_dest, table_name)

        return bucket_name, filename

    @classmethod
    def bulk_insert_from_s3(cls, bucket_name, filename, enum_db_dest, table_name, append=True):
        aws_access_key_id = os.environ.get('AWS_ACCESS_KEY_ID')
        aws_secret_access_key = os.environ.get('AWS_SECRET_ACCESS_KEY')
        con = cls.get_connection(enum_db_dest)
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
    def to_s3(cls, filename, data_table, encoding='ascii'):
        tmp_dir = '/tmp/'
        tmp_fn = tmp_dir + filename
        try:
            bucket_name = os.environ['s3-tmpfiles'] if os.environ.get('s3-tmpfiles') else 'bi-etl-ejuice-tmpfiles'
            petl.tocsv(data_table, tmp_fn, encoding=encoding)

            s3 = boto3.client('s3')
            s3.upload_file(tmp_fn, bucket_name, filename)
        except Exception as ex:
            log(ex)
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
