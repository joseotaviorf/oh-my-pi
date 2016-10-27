import os
from logging import info as log
from enum_db import EnumDb
import psycopg2
import boto3
from db_factory import DBFactory
import zipfile
import gzip
import re
import io
import petl
import json

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
