from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("S3Consumer")


class S3Consumer:
    """
    Gets data from a file path through Spark and returns it as a Spark
    DataFrame.
    :param spark_client: A client to handle the Spark connection
    :type spark_client: SparkClient
    """

    def __init__(self, spark_client):
        self.spark_client = spark_client

    @logger
    def get_data_from_file(self, path, format, options={}):
        """
        Gets the data from a file.
        :return: A Spark DataFrame with the data
        """
        return self.spark_client.get_data_from_external_source(format, options, path)
