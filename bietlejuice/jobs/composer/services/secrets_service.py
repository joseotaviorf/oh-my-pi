from bietlejuice.jobs.composer.base.spark import BaseDBUtils


class SecretsService:
    """Responsible for handling Databricks secrets operations."""

    @staticmethod
    def get_secret(key, scope="quintoandar"):
        """
        Gets the secret value from databricks environment secrets.

        :param key: secret key
        :param scope: databricks scope. Default to quintoandar
        :return: the secret value
        :rtype: string
        """
        base_dbutils = BaseDBUtils()
        if base_dbutils.get_dbutils() is not None:
            dbutils = base_dbutils.get_dbutils()

        return dbutils.secrets.get(scope, key)
