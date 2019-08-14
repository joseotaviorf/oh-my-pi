from bietlejuice.jobs.composer.base.airflow import Environment


class AmplitudeDatabaseInfo:
    @staticmethod
    def get_db_info(env):
        if not Environment.is_valid_environment(env):
            raise RuntimeError(
                "m=__init__, msg=environment %s invalid. Environments allowed are: %s"
                % (env, ", ".join(Environment.get_valid_environments()))
            )
        else:
            return {
                "db_raw_databricks": "datalake_amplitude_raw",
                "db_raw_athena": "datalake_amplitude_raw_{}".format(env),
                "db_raw_path": "s3://5a-datalake-{}/raw/amplitude/".format(env),
                "db_clean_databricks": "datalake_amplitude_clean",
                "db_clean_athena": "datalake_amplitude_clean_{}".format(env),
                "db_clean_path": "s3://5a-datalake-{}/clean/amplitude/".format(env),
            }
