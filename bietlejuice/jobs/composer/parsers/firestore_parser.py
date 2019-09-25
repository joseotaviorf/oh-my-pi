import json


class FirestoreParser:

    @staticmethod
    def parse_query(doc_ref, query):
        """Parse query.

        :param doc_ref: Collection reference object
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
        :return: Filtered collection reference object
        """
        for clause in query.keys():
            if clause == 'select':
                doc_ref = doc_ref.select(query[clause])
            if clause == 'where':
                for query_filter in query[clause]:
                    doc_ref = doc_ref.where(query_filter['field'],
                                            query_filter['op'],
                                            query_filter['value'])
            if clause == 'order_by':
                doc_ref = doc_ref.order_by(query[clause][0]['field'], query[clause][0]['direction'])
            if clause == 'limit':
                doc_ref = doc_ref.limit(query[clause])
        return doc_ref

    @staticmethod
    def parse_chunk_query(doc_ref, order_by_column, last_value, batch):
        """Parse chunk query with some statements.

        :param doc_ref: Collection reference
        :param order_by_column: Column name to sort the query
        :param last_value: Last value from order_by_column returned by this method
        :param batch: Number of documents to be returned
        :return: Query structure with parameters
        """
        next_query = (
            doc_ref
            .order_by(f'{order_by_column}')
            .start_after({
                f'{order_by_column}': last_value
            })
            .limit(batch)
        )
        return next_query

    def parse_document_type(self, docs):
        """Parse GCP Document type to json.

        :param docs: Iterator from RunQueryResponse messages.
        :return: Tuple (data_json, last_document)
        """
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
        last_document = parse_doc[-1]
        return data_json, last_document

    @staticmethod
    def convert_to_serializable_obj(obj):
        """Convert a DatetimeWithNanoSeconds object to serializable object.

        :param obj: DatetimeWithNanoSeconds object
        :return: RFC 3339-compliant timestamp (string)
        """
        return obj.rfc3339()
