from bietlejuice.clients.db_clients.glue_client import GlueClient
from bietlejuice.clients.db_clients.postgres_client import PostgresClient
from bietlejuice.clients.db_clients.spark_client import SparkClient
from bietlejuice.clients.db_clients.trino_client import TrinoClient
from bietlejuice.clients.db_clients.unity_catalog_rest_client import (
    UnityCatalogRestClient,
)

try:
    from bietlejuice.clients.db_clients.mongo_client import MongoClient
except ImportError:
    MongoClient = None  # type: ignore[assignment,misc]
