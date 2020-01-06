from bietlejuice.jobs.composer.base.airflow import Environment


class DatalakeMetastoreService:
    @staticmethod
    def get_db_info(env, source):
        Environment.validate_env(env)

        # TODO: Forno is under new AWS accounts, then use new structure
        # Prod is temporarily under old AWS account and will be migrated soon, then this
        # if clause should be removed
        if env == Environment.FORNO:
            bucket = f"datalake.s3.{env}.data.quintoandar.com.br"
            schema_suffix = ""
        else:
            schema_suffix = f"_{env}"
            bucket = f"5a-datalake-{env}"

        spark_db_infos = {
            "db_raw_databricks": f"datalake_{source}_raw",
            "db_clean_databricks": f"datalake_{source}_clean",
            "db_clean_staging_databricks": f"datalake_{source}_clean_staging",
        }

        athena_db_infos = {
            "db_raw_athena": f"datalake_{source}_raw{schema_suffix}",
            "db_clean_athena": f"datalake_{source}_clean{schema_suffix}",
            "db_clean_staging_athena": f"datalake_{source}_clean_staging{schema_suffix}",
        }

        s3_infos = {
            "db_raw_path": f"s3://{bucket}/raw/{source}/",
            "db_clean_path": f"s3://{bucket}/clean/{source}/",
            "db_clean_staging_path": f"s3://{bucket}/clean_staging/{source}/",
        }

        db_infos = {}
        db_infos.update(spark_db_infos)
        db_infos.update(athena_db_infos)
        db_infos.update(s3_infos)
        return db_infos

    @staticmethod
    def get_dw_info(env, schema):
        Environment.validate_env(env)

        # TODO: Forno is under new AWS accounts, then use new structure
        # Prod is temporarily under old AWS account and will be migrated soon, then this
        # if clause should be removed
        if env == Environment.FORNO:
            bucket = f"dw.s3.{env}.data.quintoandar.com.br"
        else:
            bucket = f"5a-dw-{env}"

        return {
            "dw_bucket": bucket,
            "dw_schema_databricks": f"dw_{schema}",
            "dw_schema_path": f"s3://{bucket}/{schema}/",
        }
