from bietlejuice.jobs.composer.base.airflow import Environment


class DWMetastoreService:
    @staticmethod
    def get_dw_info(env, schema, bucket):
        Environment.validate_env(env)

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
