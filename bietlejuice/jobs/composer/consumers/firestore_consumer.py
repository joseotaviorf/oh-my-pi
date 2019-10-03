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
    BATCH_SIZE = 10000

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
    def get_data_from_table(self, table_name):
        return self.get_data_from_table_in_chunks(table_name)

    @logger
    def get_data_from_table_in_chunks(self, table_name):
        """Get all data from table in chunks.

        :param table_name: str
        :return: spark dataframe
        """
        all_json = []

        doc_ref = self.firestore_client.collection(f"{table_name}")
        first_query = doc_ref.order_by("__name__").limit(FirestoreConsumer.BATCH_SIZE)

        old_id, current_id, snapshot, data_json, last_doc = self._get_parameters_from_query_result(
            first_query, doc_ref
        )
        all_json.append(data_json)

        while old_id != current_id:
            logger.info(
                f"m=get_data_from_table_in_chunks, msg=getting chunk data starting at id: {last_doc['firestore_id']}"
            )

            next_query = (
                doc_ref.order_by("__name__")
                .start_at(snapshot)
                .limit(FirestoreConsumer.BATCH_SIZE)
            )

            old_id, current_id, snapshot, data_json, last_doc = self._get_parameters_from_query_result(
                next_query, doc_ref, last_doc["firestore_id"]
            )
            all_json.append(data_json)
        return self._get_default_read_format_and_options(all_json)

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
        return self._get_default_read_format_and_options([data_json[0]])

    @logger(exclude="json_parsed")
    def _get_default_read_format_and_options(self, json_parsed):
        logger.info(
            f"m=_get_default_read_format_and_options, the dataframe will be written in {len(json_parsed)} partitions"
        )

        rdd = sc.parallelize(json_parsed, len(json_parsed))
        return spark.read.option("multiline", "true").json(rdd)

    def _get_parameters_from_query_result(self, query, doc_ref, current_id=None):
        if current_id:
            old_id = current_id
        else:
            old_id = ""

        docs = query.stream()
        data_json, last_doc = self.parse_file(docs)

        current_id = last_doc["firestore_id"]
        snapshot = doc_ref.document(current_id).get()
        return old_id, current_id, snapshot, data_json, last_doc

    def parse_file(self, docs):
        return self.parser.parse_document_type(docs)
