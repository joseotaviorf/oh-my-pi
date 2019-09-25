import psycopg2

from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("RedshiftClient")


class RedshiftClient:
    def __init__(self, connection_str):
        self.connection_str = connection_str

    @logger
    def run(self, query):
        try:
            connection = psycopg2.connect(
                dbname=self.connection_str["db"],
                host=self.connection_str["host"],
                port=self.connection_str["port"],
                user=self.connection_str["user"],
                password=self.connection_str["pwd"],
            )
        except Exception as e:
            raise RuntimeError(
                "m=run, msg=Error in Redshift connection., e={}".format(e)
            )

        cursor = connection.cursor()
        try:
            cursor.execute(query)
            logger.info(
                "m=run, msg=execution status message: {}".format(cursor.statusmessage)
            )
            connection.commit()
        except Exception as e:
            cursor.close()
            connection.close()
            raise RuntimeError("m=run, msg=Error in query execution., e={}".format(e))
        cursor.close()
        connection.close()
