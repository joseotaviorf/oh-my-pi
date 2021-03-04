class DatalakeMetastoreMapping:
    """Datalake properties mapping for Hive Metastore."""

    def __init__(self, source, bucket):
        """
        Constructor.

        :param source: the source name or context in metastore
        :type source: str
        :param bucket: the data lake bucket name
        :type bucket: str
        """
        self.source = source
        self.bucket = bucket

    def get_all_datalake_info(self):
        """
        Maps all the databases names and paths according to the parameters.

        :rtype: dict
        """
        database_info = {
            "db_raw_name": f"datalake_{self.source}_raw",
            "db_clean_name": f"datalake_{self.source}_clean",
            "db_enrich_name": f"datalake_{self.source}",
            "db_clean_staging_name": f"datalake_{self.source}_clean_staging",
        }

        s3_files_info = {
            "db_raw_path": f"s3a://{self.bucket}/raw/{self.source}/",
            "db_clean_path": f"s3a://{self.bucket}/clean/{self.source}/",
            "db_enrich_path": f"s3a://{self.bucket}/enrich/{self.source}/",
            "db_clean_staging_path": f"s3a://{self.bucket}/clean_staging/{self.source}/",
        }

        metastore_info = {}
        metastore_info.update(database_info)
        metastore_info.update(s3_files_info)
        return metastore_info

    def get_datalake_info_from_layer(self, layer):
        """
        Gets info for given layer.

        :param layer: raw, clean, enrich or clean_staging layers
        :type layer: str
        :return: specified layer info
        """
        metastore_info = self.get_all_datalake_info()

        datalake_database_name = metastore_info[f"db_{layer}_name"]
        database_location = metastore_info[f"db_{layer}_path"]

        return datalake_database_name, database_location
