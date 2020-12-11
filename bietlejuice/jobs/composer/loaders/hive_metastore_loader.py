from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("HiveMetastoreLoader")


class HiveMetastoreLoader:
    """
    Loads Spark DataFrame schemas into Hive Metastore as a table.

    :param metastore_service: service to interact with the Hive Metastore
    :type metastore_service: HiveMetastoreService
    """

    def __init__(self, metastore_service):
        self.hive_metastore_service = metastore_service
