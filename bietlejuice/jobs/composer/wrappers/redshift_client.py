import psycopg2

from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("RedshiftClient")


class RedshiftClient:
    def __init__(self, connection_dict):
        # TODO: research which is the best way to handle connections/cursors in psycopg2 with a multi-thread use case
        try:
            self.connection = psycopg2.connect(
                dbname=connection_dict["db"],
                host=connection_dict["host"],
                port=connection_dict["port"],
                user=connection_dict["user"],
                password=connection_dict["pwd"],
            )
        except Exception as e:
            raise RuntimeError(
                "m=run, msg=Error in Redshift connection., e={}".format(e)
            )
        self.connection.autocommit = True

    @logger
    def run_command(self, command):
        """Run a command on Redshift, do not expect a output"""
        cursor = self.connection.cursor()
        try:
            cursor.execute(command)
            logger.info(
                "m=run_command, msg=command execution status message: {}".format(
                    cursor.statusmessage
                )
            )
        except Exception as e:
            cursor.close()
            raise RuntimeError(
                "m=run_command, msg=Error in command execution., e={}".format(e)
            )
        cursor.close()

    @logger
    def run_query(self, query):
        """Run a select statement on Redshift, return the query result"""
        cursor = self.connection.cursor()
        try:
            cursor.execute(query)
            logger.info(
                "m=run_query, msg=query execution succeed, number of records returned: {}".format(
                    cursor.rowcount
                )
            )
            result = cursor.fetchall()
            cursor.close()
            return result
        except Exception as e:
            cursor.close()
            raise RuntimeError(
                "m=run_query, msg=Error in query execution., e={}".format(e)
            )
