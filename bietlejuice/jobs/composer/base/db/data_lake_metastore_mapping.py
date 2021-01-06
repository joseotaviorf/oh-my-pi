from bietlejuice.jobs.composer.base.pipeline import EnvironmentEnum


class DataLakeMetastoreMapping:
    """Data lake properties mapping for Hive Metastore."""

    def __init__(self, env, source, bucket):
        """
        Constructor.

        :param env: one of EnvironmentEnum environments
        :type env: str
        :param source: the source name or context in metastore
        :type source: str
        :param bucket: the data lake bucket name
        :type bucket: str
        """
        self.env = env
        self.source = source
        self.bucket = bucket

    def get_all_data_lake_info(self):
        """
        Maps all the databases names and paths according to the parameters.

        :rtype: dict
        """
        EnvironmentEnum.validate_env(self.env)

        # TODO: Forno is under new AWS accounts, then it uses the new structure (without suffix).
        #  Prod is temporarily under old AWS account and keeps the _prod suffix.
        #  When migrations are finished this if clause should be removed.
        if self.env == EnvironmentEnum.FORNO:
            schema_suffix = ""
        else:
            schema_suffix = f"_{self.env}"

        databricks_datalake_info = {
            "db_raw_databricks": f"datalake_{self.source}_raw",
            "db_clean_databricks": f"datalake_{self.source}_clean",
            "db_enrich_databricks": f"datalake_{self.source}",
            "db_clean_staging_databricks": f"datalake_{self.source}_clean_staging",
        }

        hive_datalake_info = {
            "db_raw_hive": f"datalake_{self.source}_raw{schema_suffix}",
            "db_clean_hive": f"datalake_{self.source}_clean{schema_suffix}",
            "db_enrich_hive": f"datalake_{self.source}{schema_suffix}",
            "db_clean_staging_hive": f"datalake_{self.source}_clean_staging{schema_suffix}",
        }

        s3_files_info = {
            "db_raw_path": f"s3a://{self.bucket}/raw/{self.source}/",
            "db_clean_path": f"s3a://{self.bucket}/clean/{self.source}/",
            "db_enrich_path": f"s3a://{self.bucket}/enrich/{self.source}/",
            "db_clean_staging_path": f"s3a://{self.bucket}/clean_staging/{self.source}/",
        }

        metastore_info = {}
        metastore_info.update(databricks_datalake_info)
        metastore_info.update(hive_datalake_info)
        metastore_info.update(s3_files_info)
        return metastore_info

    def get_data_lake_info_from_layer(self, layer):
        """
        Gets info for given layer.

        :param layer: raw, clean, enrich or clean_staging layers
        :type layer: str
        :return: specified layer info
        """
        metastore_info = self.get_all_data_lake_info()

        databricks_database_name = metastore_info[f"db_{layer}_databricks"]
        hive_database_name = metastore_info[f"db_{layer}_hive"]
        database_location = metastore_info[f"db_{layer}_path"]

        return databricks_database_name, database_location, hive_database_name
