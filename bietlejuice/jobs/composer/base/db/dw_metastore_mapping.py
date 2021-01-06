from bietlejuice.jobs.composer.base.pipeline import EnvironmentEnum


class DwMetastoreMapping:
    """DW properties mapping for Hive Metastore."""

    def __init__(self, env, schema, bucket):
        """
        Constructor.

        :param env: one of EnvironmentEnum environments
        :type env: str
        :param schema: the source name or context
        :type schema: str
        :param bucket: the data lake bucket name
        :type bucket: str
        """
        self.env = env
        self.schema = schema
        self.bucket = bucket

    def get_all_dw_info(self):
        EnvironmentEnum.validate_env(self.env)

        dw_bucket = {"dw_bucket": self.bucket}
        databricks_datalake_info = {
            "dw_staging_databricks": f"dw_{self.schema}_staging",
            "dw_schema_databricks": f"dw_{self.schema}",
        }
        s3_files_info = {
            "dw_staging_path": f"s3a://{self.bucket}/staging/{self.schema}/",
            "dw_schema_path": f"s3a://{self.bucket}/{self.schema}/",
        }

        metastore_info = {}
        metastore_info.update(dw_bucket)
        metastore_info.update(databricks_datalake_info)
        metastore_info.update(s3_files_info)

        return metastore_info
