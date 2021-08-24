from bietlejuice.jobs.composer.services.spark_services.udfs import (
    USER_DEFINED_FUNCTIONS,
)


class SparkConfiguratorService:
    """
    Service to configure spark session, for instance to register UDFs (user-defined function)
    """

    def __init__(self, spark_client, cluster_config_params):
        """
        :param spark_client: spark client to interact with spark session
        :param cluster_config_params: dict with parameters to configure spark session
        """
        self.spark_client = spark_client
        self.cluster_config_params = cluster_config_params

    def configure_spark_session(self):
        """
        Configure spark session using parameters provide. For now it only registers UDFs.
        """
        if self.cluster_config_params["udfs"]:
            for udf in self.cluster_config_params["udfs"]:
                self.register_udf(udf)

    def register_udf(self, udf_identifier):
        """
        Register UDF into spark session

        :param udf_identifier: the name of UDF
            (that was previously defined in /spark_services/udfs/__init__.py)
        :type udf_identifier: str
        """
        udf = USER_DEFINED_FUNCTIONS[udf_identifier]
        if udf:
            self.spark_client.conn.udf.register(udf_identifier, udf)
