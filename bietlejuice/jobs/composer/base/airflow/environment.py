class Environment:
    FORNO = "forno"
    PROD = "prod"

    @classmethod
    def is_valid_environment(cls, environment):
        return environment in cls.get_valid_environments()

    @classmethod
    def get_valid_environments(cls):
        return [cls.FORNO, cls.PROD]
