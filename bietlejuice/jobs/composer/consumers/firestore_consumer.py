from quintoandar_logger import QuintoAndarLogger

import firebase_admin
from firebase_admin import credentials, firestore
from bietlejuice.jobs.composer.base.db import DatabaseTypeEnum
from bietlejuice.jobs.composer.parsers.firestore_parser import FirestoreParser
from bietlejuice.jobs.composer.consumers.database_consumer import DatabaseConsumer
from bietlejuice.jobs.composer.base.spark import BaseSparkContext


logger = QuintoAndarLogger("FirestoreConsumer")
spark, sc = BaseSparkContext.spark, BaseSparkContext.sc


class FirestoreConsumer(DatabaseConsumer):
    BATCH_SIZE = 5000

    def __init__(self, connection):
        if connection["dbtype"].lower() != DatabaseTypeEnum.FIRESTORE:
            raise RuntimeError(
                f"m=__init__, con_type={connection.get('dbtype')}, "
                f"msg=Connection is not a firestore connection"
            )

        cred = credentials.Certificate(connection["credentials"])
        firebase_admin.initialize_app(cred)

        self.firestore_client = firestore.client()
        self.parser = FirestoreParser()

    @logger
    def get_table_names_and_sizes(self):
        all_collections = self.firestore_client.collections()
        tables = [
            {"table_name": collection.id, "size": 0} for collection in all_collections
        ]
        return self._get_default_read_format_and_options(tables)

    @logger
    def get_data_from_table(self, table, order_by_column, last_doc=None):
        """Get all data from table in chunks.

        :param table: Table name
        :param order_by_column: Column name to sort the query
        :param last_doc: Last value from query returned by this method
        :return: Tuple (spark dataframe, last_document)
        """
        doc_ref = self.firestore_client.collection(f"{table}")

        if not last_doc:
            first_query = doc_ref.order_by(f"{order_by_column}").limit(
                FirestoreConsumer.BATCH_SIZE
            )
            docs = first_query.stream()
            data_json, last_document = self.parse_file(docs)
            return self._get_default_read_format_and_options(data_json), last_document

        last_pop = last_doc[f"{order_by_column}"]
        next_query = self.parser.parse_chunk_query(
            doc_ref, order_by_column, last_pop, FirestoreConsumer.BATCH_SIZE
        )
        docs = next_query.stream()
        data_json, last_document = self.parse_file(docs)
        return self._get_default_read_format_and_options(data_json), last_document

    @logger
    def get_data_from_query(self, query, table_name=None):
        """Get data from query.

        :param query: Json with statements. For example:
            {
                "select": ["createdDate", "iteration", "firestore_id", "ownerId"],
                "where": [
                    {
                        "field": "lastSentDate",
                        "op": ">=",
                        "value": "2018-9-19"
                    },
                    {
                        "field": "lastSentDate",
                        "op": "<",
                        "value": "2019-9-20"
                    }
                ],
                "order_by": [
                    {
                        "field": "lastSentDate",
                        "direction": "ASCENDING"
                    }
                ],
                "limit": 5000
            }
        :param table_name: string
        :return: spark dataframe
        """
        doc_ref = self.firestore_client.collection("{}".format(table_name))

        doc_ref_parsed = self.parser.parse_query(doc_ref, query)
        docs = doc_ref_parsed.stream()
        data_json = self.parse_file(docs)
        return self._get_default_read_format_and_options(data_json[0])

    @logger(exclude="json_parsed")
    def _get_default_read_format_and_options(self, json_parsed):
        rdd = sc.parallelize([json_parsed], 3)
        return spark.read.option("multiline", "true").json(rdd)

    def parse_file(self, docs):
        return self.parser.parse_document_type(docs)
