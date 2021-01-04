class EnvironmentEnum:
    """Databricks/Spark jobs environment enum"""

    FORNO = "forno"
    PROD = "prod"

    @classmethod
    def is_valid_environment(cls, environment):
        return environment in cls.get_valid_environments()

    @classmethod
    def get_valid_environments(cls):
        return [cls.FORNO, cls.PROD]

    @staticmethod
    def validate_env(env):
        if not EnvironmentEnum.is_valid_environment(env):
            valid_envs = ", ".join(EnvironmentEnum.get_valid_environments())
            raise RuntimeError(
                f"m=Environment.validate_env, msg=environment {env} invalid. "
                f"Environments allowed are: {valid_envs}"
            )

        return True
