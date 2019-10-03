from bietlejuice.jobs.composer.base.airflow import Environment


class DatalakeMetastoreService:
    @staticmethod
    def get_db_info(env, source):
        if not Environment.is_valid_environment(env):
            raise RuntimeError(
                "m=__init__, msg=environment %s invalid. Environments allowed are: %s"
                % (env, ", ".join(Environment.get_valid_environments()))
            )

        return {
            "db_raw_databricks": "datalake_{}_raw".format(source),
            "db_raw_athena": "datalake_{}_raw_{}".format(source, env),
            "db_raw_path": "s3://5a-datalake-{}/raw/{}/".format(env, source),
            "db_clean_databricks": "datalake_{}_clean".format(source),
            "db_clean_athena": "datalake_{}_clean_{}".format(source, env),
            "db_clean_path": "s3://5a-datalake-{}/clean/{}/".format(env, source),
        }

    @staticmethod
    def get_dw_info(env, schema):
        if not Environment.is_valid_environment(env):
            raise RuntimeError(
                "m=__init__, msg=environment %s invalid. Environments allowed are: %s"
                % (env, ", ".join(Environment.get_valid_environments()))
            )

        return {
            "dw_schema_databricks": "dw_{}".format(schema),
            "dw_schema_path": "s3://5a-dw-{}/{}/".format(env, schema),
        }
