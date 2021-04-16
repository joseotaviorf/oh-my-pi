import json

from datetime import datetime
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
        query = {"collstats": collection_name, "scale": 1024}
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

        try:
            df = self.spark_client.create_dataframe(converted_data)
        except ValueError:
            logger.warning(
                "m=__convert_bson_documents_to_spark_dataframe, msg=Spark DataFrame is empty"
            )
            df = None

        return df

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

    @logger
    def get_data_from_table_in_parallel(self, table_name, concurrency):
        # todo: implement me!
        raise NotImplementedError()

    @logger(exclude_return=True)
    def get_incremental_data_from_table(self, table_name, column_name, execution_date):
        """
        Gets incremental data from a collection of a Mongo database, applying
        a given input date string as a filter in a given column or nested column.
        The filter is agnostic to the column type: it will filter "datetime" type,
        "%Y-%m-%dT%H:%m:%sZ" date string type or "%Y-%m-%d" date string type columns
        for any date string input given.
        :param table_name: Name of the table
        :param column_name: Name of the column to which the filter will be applied.
            In case of a nested column, a dot (.) must be between the nest field and
            the nested column.
            e. g. "tasks.updated_at"
        :param execution_date: Date filter value.
        :type execution_date: date str in format %Y-%m-%d
        :return: A Spark DataFrame with the table data
        """
        # Validates the date string format:
        execution_datetime = datetime.strptime(execution_date, "%Y-%m-%d")

        # Validates if the date column exists in table:
        single_record = self.get_record_sample(table_name, column_name)

        # Verifies if the column is nested:
        nest_value = None
        if "." in column_name:
            nest_field, nested_field = column_name.split(".")
            nest_value = single_record.get(nest_field)
            column_value = (
                nest_value[0].get(nested_field)
                if isinstance(nest_value, list)
                else nest_value.get(nested_field)
            )
        else:
            column_value = single_record.get(column_name)

        # Verifies datatype of the date column:
        if isinstance(column_value, datetime):
            dt_start = execution_datetime.replace(hour=0, minute=0, second=0)
            dt_end = execution_datetime.replace(hour=23, minute=59, second=59)
        elif isinstance(column_value, str):
            dt_start = f"{execution_date}T00:00:00Z"
            dt_end = f"{execution_date}T23:59:59Z"

        # Composes a query for a nested or an unnested column:
        if isinstance(nest_value, list):
            query = {
                nest_field: {
                    "$elemMatch": {nested_field: {"$gte": dt_start, "$lte": dt_end}}
                }
            }
        else:
            query = {column_name: {"$gte": dt_start, "$lte": dt_end}}

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

    @logger(exclude_return=True)
    def get_record_sample(self, table_name, column_name=None):
        """
        Gets a record sample from a specific table. If a `column_name` is given,
        the record returned is the first in which the column exists and is not null.
        :param table_name: Name of the table where the column will be looked for
        :param type: string
        :param column_name: Name of the column used to find a record. If given, the record
            returned will be the first in which the column exists and is not null.
            In case of a nested column, a dot (.) must separate the array and the column.
            e. g. "tasks.updated_at"
        :param type: string
        :return: dict
        """
        args = [{column_name: {"$exists": True, "$ne": None}}] if column_name else []
        record_sample = self.mongo_client.conn[self.mongo_client.db][
            table_name
        ].find_one(*args)
        if not record_sample:
            raise KeyError(
                f"There are no values for '{column_name}' in '{table_name}' table"
            )
        return record_sample
