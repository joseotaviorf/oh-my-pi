import json

from pyspark.sql import SparkSession
from quintoandar_logger import QuintoAndarLogger

import firebase_admin
from firebase_admin import (credentials, firestore)
from bietlejuice.jobs.composer.base.db import DatabaseTypeEnum
from bietlejuice.jobs.composer.consumers.database_consumer import DatabaseConsumer

logger = QuintoAndarLogger("FirestoreConsumer")


class FirestoreConsumer(DatabaseConsumer):
    def __init__(self, connection):
        if connection['dbtype'].lower() != DatabaseTypeEnum.FIRESTORE:
            raise RuntimeError(
                f"m=__init__, con_type={connection.get('dbtype')}, "
                f"msg=Connection is not a postgresql connection"
            )

        cred = credentials.Certificate(connection['credentials'])
        firebase_admin.initialize_app(cred)

        self.connection = firestore.client()
        # self.client = self.connection._firestore_api()

    @logger
    def get_table_names_and_sizes(self):
        all_collections = self.connection.collections()
        return [{'table_name': collection.id, 'size': 0} for collection in all_collections]

    @logger
    def get_data_from_table(self, table):
        doc_ref = self.connection.collection('{}'.format(table))
        docs = doc_ref.get()

        parse_doc = []
        index = 0
        for doc in docs:
            parse_doc.append([doc.to_dict()])
            parse_doc[index][0]["firestore_id"] = doc.id
            index += 1

        if len(parse_doc) > 0:
            data_json = "\n".join(
                json.dumps(
                    doc[0], default=self.convert_to_serializable_obj, sort_keys=True
                )
                for doc in parse_doc
            )

        return self._get_default_read_format_and_options(data_json)

    def convert_to_serializable_obj(self, obj):
        return obj.rfc3339()

    @logger
    def get_data_from_table_in_parallel(self, table_name, concurrency):
        raise NotImplementedError()

    @logger
    def get_data_from_query(self, query, table_name=None):
        client = self.connection._firestore_api()
        doc_ref = self.connection.collection(u'{}'.format(table_name))

    @logger
    def get_table_schema(self, table_name):
        raise NotImplementedError()

    @logger
    def _get_default_read_format_and_options(self, json_parsed):
        spark = SparkSession.builder.getOrCreate()
        rdd = spark.parallelize(json_parsed)

        return spark.read.option('multiline', 'true').json(rdd)

    @logger
    def _get_partition_column_from_table(self, table):
        raise NotImplementedError()
