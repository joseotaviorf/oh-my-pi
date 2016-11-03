from logging import info as log
from enum_db import EnumDb
import boto3
from db_factory import DBFactory
import zipfile
import gzip
import re
import io
import petl
import json
import os


class BaseETL:

    def __init__(self):
        pass

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
    def get_connection(db_enum):
        return DBFactory.get_connection(db_enum)

    @staticmethod
    def to_db(db_enum, data_table, table_name, append=True):
        conn = BaseETL.get_connection(db_enum)
        if append:
            petl.appenddb(data_table, conn, table_name)
        else:
            petl.todb(data_table, conn, table_name)

    @staticmethod
    def from_db_table(db_enum, table_name):
        return BaseETL.from_db_query(db_enum=db_enum, query='SELECT * FROM {}'.format(table_name))

    @staticmethod
    def from_db_query(db_enum, query):
        conn = BaseETL.get_connection(db_enum)
        return list(petl.fromdb(conn, query))

    @staticmethod
    def move_table(table_name, enum_db_source, enum_db_dest):
        aws_access_key_id = os.environ['AWS_ACCESS_KEY_ID']
        aws_secret_access_key = os.environ['AWS_SECRET_ACCESS_KEY']
        tmp_dir = '/tmp/'
        fn = '{}.csv'.format(table_name)
        tmp_fn = tmp_dir+fn
        bucket_name =os.environ['s3-tmpfiles'] if os.environ.get('s3-tmpfiles') else 'bi-etl-ejuice-tmpfiles'

        dim = BaseETL.from_db_table(db_enum=enum_db_source, table_name=table_name)
        petl.tocsv(dim, tmp_fn)

        s3 = boto3.client('s3')
        s3.upload_file(tmp_fn, bucket_name, fn)

        os.remove(tmp_fn)

        con = BaseETL.get_connection(enum_db_dest)
        sql = """COPY {} FROM '{}'
                    CREDENTIALS 'aws_access_key_id={};aws_secret_access_key={}'
                    DELIMITER '{}' FORMAT CSV IGNOREHEADER 1; commit;""".format(
            table_name,
            's3://{}/{}'.format(bucket_name, fn),
            aws_access_key_id,
            aws_secret_access_key,
            ',')
        try:
            con.cursor().execute(sql)
        finally:
            con.close()
            BaseETL.delete_file_s3(bucket_name, fn)

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
