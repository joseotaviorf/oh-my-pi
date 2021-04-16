from pymongo import MongoClient as Connection

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.clients.db_clients.db_client import DBClient

logger = QuintoAndarLogger("MongoClient")


class MongoClient(DBClient):
    def __init__(self, conn_config):
        """
        this method build the URI format to connection with MongoDB using pymongo library.
        :param conn_config: A dict with the config values of the connection.
        :format conn_config: the dict format is:
            {
                  "host": str, (optional, if there are only replicas)
                  "replicas": list, (optional, if there is only host)
                  "port": str,
                  "db": str,
                  "user": str,
                  "pwd": str,
                  "dbtype": "mongo",
                  "params": json (optional)
            }
        """
        hosts = []
        if "host" in conn_config:
            hosts.append(conn_config["host"] + ":" + conn_config["port"])

        if "replicas" in conn_config and isinstance(conn_config["replicas"], list):
            hosts.extend(
                [h + ":" + conn_config["port"] for h in conn_config["replicas"]]
            )

        self.hosts = ",".join(hosts)
        self.db = conn_config["db"]
        self.uri = f"mongodb://{conn_config['user']}:{conn_config['pwd']}@{self.hosts}/{self.db}"

        if "params" in conn_config:
            params = [k + "=" + v for k, v in conn_config["params"].items()]
            params = "?" + "&".join(params)
            self.uri += params

    @property
    def conn(self):
        """
        Returns a connection object.
        """
        return Connection(self.uri)

    @logger
    def get_records(self, query, parameters=None):
        logger.error(
            """
          `get_records` is not implemented in MongoClient because the MongoDB does not have the concept of tables and records.
          If you want to query a collection and get the documents, try the `get_documents` method.
          """
        )
        raise NotImplementedError()

    @logger(exclude_return=True)
    def get_documents(self, mongo_collection, query, **kwargs):
        """
        Execute query in a specific Collection and return its result.
        :param mongo_collection: Name of the collection
        :param query: query content
        :type query: dict
        :return: list of documents
        """
        with self.conn as conn:
            collection = conn[self.db][mongo_collection]
            documents = collection.find(query, **kwargs)
            logger.info(
                f"m=get_documents, nb_documents={documents.count()}, msg=query execution succeeded"
            )
            return documents

    @logger(exclude_return=True)
    def run(self, command, parameters=None):
        """
            Execute command in Database
            :param command: command content
            :type command: dict
            :param parameters: optional parameters
            :type command: dict
        """
        with self.conn as conn:
            if parameters is not None:
                response = conn[self.db].command(command)
            else:
                response = conn[self.db].command(command, parameters)
            return response
