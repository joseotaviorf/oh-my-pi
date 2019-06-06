import abc

from python_logger import QuintoAndarLogger

logger = QuintoAndarLogger('Consumer')


class Consumer(abc.ABC):

    @abc.abstractmethod
    def get_table_names_and_sizes(self):
        pass

    @abc.abstractmethod
    def get_data_from_table(self, table):
        pass

    @abc.abstractmethod
    def get_data_from_table_in_parallel(self, table, concurrency):
        pass

    @abc.abstractmethod
    def get_data_from_query(self, query):
        pass

    @abc.abstractmethod
    def get_table_schema(self, table):
        pass

    @logger
    def is_db_empty(self):
        result = None
        try:
            result = self.get_table_names_and_sizes()
        except Exception as e:
            logger.error('m=is_db_empty, msg=Database of this consumer does not exist., e={}'.format(e))
        if result and result.count():
            return False

        return True
