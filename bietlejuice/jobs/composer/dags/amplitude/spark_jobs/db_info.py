class AmplitudeDatabaseInfo:
    @staticmethod
    def get_db_info(env):
        if env == "forno":
            return {
                "db_raw_databricks": "datalake_amplitude_raw",
                "db_raw_athena": "datalake_amplitude_raw_forno",
                "db_raw_path": "s3://5a-datalake-forno/raw/amplitude/",
                "db_clean_databricks": "datalake_amplitude_clean",
                "db_clean_athena": "datalake_amplitude_clean_forno",
                "db_clean_path": "s3://5a-datalake-forno/clean/amplitude/",
            }
        elif env == "prod":
            return {
                "db_raw_databricks": "datalake_amplitude_raw",
                "db_raw_athena": "datalake_amplitude_raw_prod",
                "db_raw_path": "s3://5a-datalake-prod/raw/amplitude/",
                "db_clean_databricks": "datalake_amplitude_clean",
                "db_clean_athena": "datalake_amplitude_clean_prod",
                "db_clean_path": "s3://5a-datalake-prod/clean/amplitude/",
            }
        raise ValueError("The environment do not exists: {}".format(env))
