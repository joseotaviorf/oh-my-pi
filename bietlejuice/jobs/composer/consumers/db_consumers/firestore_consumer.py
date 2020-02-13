import firebase_admin
from firebase_admin import credentials, firestore
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatabaseTypeEnum
from bietlejuice.jobs.composer.base.spark import BaseSparkContext
from bietlejuice.jobs.composer.consumers.db_consumers.db_consumer import DBConsumer
from bietlejuice.jobs.composer.parsers.firestore_parser import FirestoreParser

logger = QuintoAndarLogger("FirestoreConsumer")
spark, sc = BaseSparkContext.spark, BaseSparkContext.sc  # todo: remove this


class FirestoreConsumer(DBConsumer):
    """
    This class is deprecated at the moment. If you want to use it, please,
    check the other database consumers (e.g. PostgresConsumer, DatabricksConsumer) and
    refactor it. Try to use the SparkClient class to read data from Firestore and
    return Spark DataFrames in the inherited methods (defined by the interface
    DBConsumer), however, if this is not possible you can create a FirestoreClient to
    handle the low level communication with Firestore (check the interface DBClient)
    and return other types of objects in the inherited methods. In any case, you need
    to remove the spark code in this class (spark, sc). Also, favor dependency
    injection and avoid spark code in this class.
    """

    BATCH_SIZE = 10000

    def __init__(self, conn_config):
        if conn_config["dbtype"].lower() != DatabaseTypeEnum.FIRESTORE:
            raise RuntimeError(
                f"m=__init__, con_type={conn_config.get('dbtype')}, "
                f"msg=Connection is not a firestore connection"
            )

        cred = credentials.Certificate(conn_config["credentials"])
        firebase_admin.initialize_app(cred)

        self.firestore_client = firestore.client()
        self.parser = FirestoreParser()

    @logger
    def get_table_names_and_sizes(self):
        all_collections = self.firestore_client.collections()
        tables = [
            {"table_name": collection.id, "size": 0} for collection in all_collections
        ]
        return self._get_default_read_format_and_options(tables)  # todo: remove this

    @logger
    def get_data_from_table(self, table_name):
        all_json = []

        doc_ref = self.firestore_client.collection(f"{table_name}")
        old_id, current_id, snapshot, data_json, last_doc = self._get_first_chunk(
            doc_ref
        )
        all_json.append(data_json)

        return self._get_data_in_chunks(
            doc_ref, snapshot, last_doc["firestore_id"], old_id, current_id, all_json
        )

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
        # todo: remove the below method call
        return self._get_default_read_format_and_options([data_json[0]])

    @logger(exclude="json_parsed")
    def _get_default_read_format_and_options(self, json_parsed):
        # todo: remove this method
        logger.info(
            f"m=_get_default_read_format_and_options, the dataframe will be written "
            f"in {len(json_parsed)} partitions"
        )

        rdd = sc.parallelize(json_parsed, len(json_parsed))
        return spark.read.option("multiline", "true").json(rdd)

    def _get_first_chunk(self, doc_ref):
        first_query = doc_ref.order_by("__name__").limit(FirestoreConsumer.BATCH_SIZE)
        return self._get_parameters_from_query_result(first_query, doc_ref)

    def _get_data_in_chunks(
        self, doc_ref, snapshot, firestore_id, old_id, current_id, all_json
    ):
        while old_id != current_id:
            logger.info(
                f"m=get_data_from_table_in_chunks, msg=getting data chunk starting at "
                f"id: {current_id}"
            )

            next_query = (
                doc_ref.order_by("__name__")
                .start_at(snapshot)
                .limit(FirestoreConsumer.BATCH_SIZE)
            )
            (
                old_id,
                current_id,
                snapshot,
                data_json,
                last_doc,
            ) = self._get_parameters_from_query_result(next_query, doc_ref, current_id)
            all_json.append(data_json)
        return self._get_default_read_format_and_options(all_json)  # todo: remove this

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

    @logger
    def get_data_from_table_in_parallel(self, table_name, concurrency):
        # todo: implement me!
        raise NotImplementedError()

    @logger
    def get_table_schema(self, table_name):
        # todo: implement me!
        raise NotImplementedError()

    @logger
    def get_incremental_data_from_table(self, table_name, column_name, execution_date):
        # todo: implement me!
        raise NotImplementedError()
