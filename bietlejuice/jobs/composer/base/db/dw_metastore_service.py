from bietlejuice.jobs.composer.base.pipeline import EnvironmentEnum


class DWMetastoreService:
    @staticmethod
    def get_dw_info(env, schema, bucket):
        EnvironmentEnum.validate_env(env)

        dw_bucket = {"dw_bucket": bucket}
        spark_db_infos = {
            "dw_staging_databricks": f"dw_{schema}_staging",
            "dw_schema_databricks": f"dw_{schema}",
        }
        s3_infos = {
            "dw_staging_path": f"s3://{bucket}/staging/{schema}/",
            "dw_schema_path": f"s3://{bucket}/{schema}/",
        }

        db_infos = {}
        db_infos.update(dw_bucket)
        db_infos.update(spark_db_infos)
        db_infos.update(s3_infos)

        return db_infos

    @staticmethod
    def get_layer_info(env, schema, bucket, layer):
        """
        Return specified layer info
        :param env: forno or prod environments
        :param schema: schema name in metastore
        :param bucket: dw bucket in S3
        :param layer: staging or schema layers
        :return: specified layer info
        """
        db_info = DWMetastoreService.get_dw_info(env, schema, bucket)

        schema_database_name = db_info["dw_" + layer + "_databricks"]
        schema_database_location = db_info["dw_" + layer + "_path"]

        return schema_database_name, schema_database_location
