import json
from quintoandar_logger import QuintoAndarLogger

import firebase_admin
from firebase_admin import (credentials, firestore)
from bietlejuice.jobs.composer.base.db import DatabaseTypeEnum
from bietlejuice.jobs.composer.consumers.database_consumer import DatabaseConsumer
from bietlejuice.jobs.composer.base.spark import BaseSparkContext


logger = QuintoAndarLogger("FirestoreConsumer")
spark, sc = BaseSparkContext.spark, BaseSparkContext.sc


class FirestoreConsumer(DatabaseConsumer):
    def __init__(self, connection):
        if connection['dbtype'].lower() != DatabaseTypeEnum.FIRESTORE:
            raise RuntimeError(
                f"m=__init__, con_type={connection.get('dbtype')}, "
                f"msg=Connection is not a postgresql connection"
            )

        cred = credentials.Certificate(connection['credentials'])
        firebase_admin.initialize_app(cred)

        self.db = firestore.client()

    @logger
    def get_table_names_and_sizes(self):
        all_collections = self.db.collections()
        tables = [{'table_name': collection.id, 'size': 0} for collection in all_collections]
        return self._get_default_read_format_and_options(tables)

    @logger
    def get_data_from_table(self, table):
        doc_ref = self.db.collection('{}'.format(table)).limit(100)
        docs = doc_ref.get()

        data_json = self.parse_file(docs)
        return self._get_default_read_format_and_options(data_json)

    @logger
    def get_data_from_query(self, query, table_name=None):
        doc_ref = self.db.collection(u'{}'.format(table_name))

        for clause in query.keys():
            if clause == 'select':
                doc_ref = doc_ref.select(query[clause])
            if clause == 'where':
                for query_filter in query[clause]:
                    doc_ref = doc_ref.where(query_filter['field'],
                                            query_filter['op'],
                                            query_filter['value'])
            if clause == 'order_by':
                doc_ref = doc_ref.order_by(query[clause]['field'], query[clause]['direction'])
            if clause == 'limit':
                doc_ref = doc_ref.limit(query[clause])

        docs = doc_ref.stream()
        data_json = self.parse_file(docs)
        return self._get_default_read_format_and_options(data_json)

    def parse_file(self, docs):
        parse_doc = []

        for doc in docs:
            row = doc.to_dict()
            row['firestore_id'] = doc.id
            parse_doc.append(row)

        if len(parse_doc) > 0:
            data_json = json.dumps(
                [doc for doc in parse_doc],
                default=self.convert_to_serializable_obj,
                sort_keys=True
            )

            return data_json

    @logger(exclude='json_parsed')
    def _get_default_read_format_and_options(self, json_parsed):
        rdd = sc.parallelize([json_parsed], 20)
        return spark.read.option('multiline', "true").json(rdd)

    def convert_to_serializable_obj(self, obj):
        return obj.rfc3339()

    def get_data_from_table_in_parallel(self, table_name, concurrency):
        raise NotImplementedError

    def get_table_schema(self, table_name):
        raise NotImplementedError
