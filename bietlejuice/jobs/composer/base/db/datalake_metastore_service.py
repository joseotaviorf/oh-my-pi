from deprecated import deprecated

from bietlejuice.jobs.composer.base.pipeline import EnvironmentEnum


@deprecated(
    reason="""
This module is discontinued and shall be removed when Athena is migrated to Presto and Hive Metastore.
The datalake_metastore_mapping.py is the new mapping file for Hive metastore.
"""
)
class DatalakeMetastoreService:
    @staticmethod
    def get_db_info(env, source, bucket):
        EnvironmentEnum.validate_env(env)

        # TODO: Forno is under new AWS accounts, then it uses the new structure (without suffix).
        #  Prod is temporarily under old AWS account and keeps the _prod suffix.
        #  When migrations are finished this if clause should be removed.
        if env == EnvironmentEnum.FORNO:
            schema_suffix = ""
        else:
            schema_suffix = f"_{env}"

        spark_db_infos = {
            "db_raw_databricks": f"datalake_{source}_raw",
            "db_clean_databricks": f"datalake_{source}_clean",
            "db_enrich_databricks": f"datalake_{source}",
            "db_clean_staging_databricks": f"datalake_{source}_clean_staging",
        }

        athena_db_infos = {
            "db_raw_athena": f"datalake_{source}_raw{schema_suffix}",
            "db_clean_athena": f"datalake_{source}_clean{schema_suffix}",
            "db_enrich_athena": f"datalake_{source}{schema_suffix}",
            "db_clean_staging_athena": f"datalake_{source}_clean_staging{schema_suffix}",
        }

        s3_infos = {
            "db_raw_path": f"s3://{bucket}/raw/{source}/",
            "db_clean_path": f"s3://{bucket}/clean/{source}/",
            "db_enrich_path": f"s3://{bucket}/enrich/{source}/",
            "db_clean_staging_path": f"s3://{bucket}/clean_staging/{source}/",
        }

        db_infos = {}
        db_infos.update(spark_db_infos)
        db_infos.update(athena_db_infos)
        db_infos.update(s3_infos)
        return db_infos

    @staticmethod
    def get_layer_info(env, source, bucket, layer):
        """
        Return specified layer info
        :param env: forno or prod environments
        :param source: source or context name in metastore
        :param bucket: datalake bucket in S3
        :param layer: raw, clean, enrich or clean_staging layers
        :return: specified layer info
        """
        db_info = DatalakeMetastoreService.get_db_info(env, source, bucket)

        database_name = db_info["db_" + layer + "_databricks"]
        database_location = db_info["db_" + layer + "_path"]
        athena_database_name = db_info["db_" + layer + "_athena"]

        return database_name, database_location, athena_database_name
