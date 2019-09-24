import json


class FirestoreParser:

    @staticmethod
    def parse_query(doc_ref, query):
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
        return doc_ref

    @staticmethod
    def parse_chunk_query(doc_ref, order_by_column, last_value, batch):
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
        return obj.rfc3339()
