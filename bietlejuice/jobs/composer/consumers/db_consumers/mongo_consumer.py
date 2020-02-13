import json
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.consumers.db_consumers.db_consumer import DBConsumer
from bietlejuice.jobs.composer.services import JsonService

from bson.json_util import dumps as bson_dumps, RELAXED_JSON_OPTIONS

logger = QuintoAndarLogger("MongoConsumer")


class MongoConsumer(DBConsumer):
    """
    Gets data from a Mongo database through MongoClient passed by param and
    returns it as a Spark Dataframe.
    :mongo_client: A client to handle the Mongo connection
    :type mongo_client: MongoClient
    :spark_client: A client to handle the Spark connection
    :type spark_client: SparkClient
    """

    def __init__(self, mongo_client, spark_client):
        self.mongo_client = mongo_client
        self.spark_client = spark_client

    @logger
    def _get_collection_names(self):
        """
            Gets the collection names of a Mongo database.
            :return: A list of collection names
        """
        query = {
            "listCollections": 1.0,
            "authorizedCollections": True,
            "nameOnly": True,
        }
        collections = self.mongo_client.run(query)["cursor"]["firstBatch"]
        collection_names = []

        for coll in collections:
            collection_names.append(coll["name"])

        return collection_names

    @logger
    def _estimate_collection_size(self, collection_name):
        """
        Calculates an estimated value for the size of a collection
        :param collection_name: The name of the collection
        :return: The estimated value for the size
        """
        query = {"collstats": collection_name, "scale": 1048576}
        collection_size = self.mongo_client.run(query)["size"]

        return collection_size

    @logger
    def get_table_names_and_sizes(self):
        """
        Gets the collection names and sizes of a Mongo database.
        :return: A Spark Dataframe with cols: name and size
        """
        collection_names = self._get_collection_names()
        collections = [
            {"table_name": coll_name, "size": self._estimate_collection_size(coll_name)}
            for coll_name in collection_names
        ]
        df = self.spark_client.create_dataframe(collections)
        return df

    @logger(exclude="data", exclude_return=True)
    def __convert_columns_to_string_type(self, data):
        """
        Converts all columns of a dict or a list of dict to string type.
        :param data: the data that must be converted.
        :type data: dict or list of dict
        """
        converted_data = []
        if isinstance(data, list):
            for item in data:
                converted_data.append(
                    JsonService.transform_columns_type_to_string(item)
                )
        else:
            converted_data.append(JsonService.transform_columns_type_to_string(data))

        return converted_data

    @logger(exclude_return=True)
    def __convert_bson_documents_to_spark_dataframe(self, documents):
        """
        Converts [a list of] bson documents to spark_dataframe using bson_dumps
        :param documents: return get_documents method in MongoClient
        :type documents: list of bson documents or a bson document
        :return: A Spark DataFrame with all columns of the string type
        """
        # documents are a list of Bson (Mongo format), it's necessary to convert to dict.
        # convert  bson -> json_string -> dict
        data = json.loads(bson_dumps(documents, json_options=RELAXED_JSON_OPTIONS))
        converted_data = self.__convert_columns_to_string_type(data)
        return self.spark_client.create_dataframe(converted_data)

    @logger(exclude_return=True)
    def get_data_from_table(self, table_name):
        """
        Gets all data from a collection in a Mongo database.
        :param table_name: Name of the table
        :return: A Spark DataFrame with the table data
        OBS: ALL fields are converted to string type
        """
        query = {}
        df = self.get_data_from_query(table_name, query)
        return df

    @logger(exclude_return=True)
    def get_incremental_data_from_table(self, table_name, column_name, execution_date):
        """
        Gets incremental data from a collection in a Mongo Database.
        The method expects a column table that contains a date to make the filter.
        :param table_name: Name of the table
        :param column_name: Name of the column to make the filter
        :param execution_date: Value of the column
        :type execution_date: date str in format %Y-%m-%d
        :return: A Spark DataFrame with the table data
        OBS: ALL fields are converted to string type
        """
        start_date = execution_date + "T00:00:00Z"
        end_date = execution_date + "T23:59:59Z"

        # the query verifies if the value of the column is between start_date and end_date
        # and handles when the column is a timestamp or/and string.
        query = {
            "$or": [
                {"$and": [{column_name: {"$gte": start_date, "$lte": end_date}}]},
                {
                    "$and": [
                        {
                            column_name: {
                                "$gte": {"$date": start_date},
                                "$lte": {"$date": end_date},
                            }
                        }
                    ]
                },
                {column_name: execution_date},
            ]
        }

        df = self.get_data_from_query(table_name, query)
        return df

    @logger(exclude_return=True)
    def get_data_from_query(self, table_name, query):
        """
        Gets the results of a query in a Mongo database.
        :param query: Query content
        :param type: dict
        :param table_name: Name of the table relevant to the query
        :return: A Spark DataFrame with the query results.
        OBS: ALL fields are converted to string type
        """
        documents = self.mongo_client.get_documents(table_name, query)
        df = self.__convert_bson_documents_to_spark_dataframe(documents)
        return df

    @logger
    def get_table_schema(self, query, table_name=None):
        logger.error(
            """
        `get_table_schema` is not implemented in MongoConsumer because the MongoDB does not have
        the concept of schema. The methods `get_data_*` already infer on the data to create the
        Spark DataFrame.
        """
        )
        raise NotImplementedError()
