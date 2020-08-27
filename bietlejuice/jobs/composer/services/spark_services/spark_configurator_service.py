from bietlejuice.jobs.composer.services.spark_services.udfs import UDFS


class SparkConfiguratorService:
    """
    Service to configure spark session, for instance to register UDFs (user-defined function)
    """

    def __init__(self, spark_client, spark_params):
        """
        :param spark_client: spark client to interact with spark session
        :param spark_params: dict with parameters to configure spark session
        """
        self.spark_client = spark_client
        self.spark_params = spark_params

    def configure_spark_session(self):
        """
        Configure spark session using parameters provide. For now it registers UDFs.
        """
        if self.spark_params["udfs"]:
            for udf in self.spark_params["udfs"]:
                self.register_udf(udf)

    def register_udf(self, udf_identifier):
        """
        Register UDF into spark session
        :param self:
        :param udf_identifier:
        :return:
        """
        udf = UDFS[udf_identifier]
        if udf:
            self.spark_client.conn.udf.register(udf_identifier, udf)
