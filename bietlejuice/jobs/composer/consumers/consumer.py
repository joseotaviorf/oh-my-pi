import abc
import json
import os

from python_logger import QuintoAndarLogger

logger = QuintoAndarLogger('Consumer')


class Consumer(abc.ABC):

    @logger
    def get_connection(self, db_enum):
        try:
            env = json.loads(os.environ.get(db_enum))
        except TypeError as e:
            raise RuntimeError('m=Consumer, msg={} is not a valid connection in Airflow, e={}'.format(db_enum, e))

        return env

    @abc.abstractmethod
    def get_table_names_and_sizes(self):
        pass

    @abc.abstractmethod
    def get_data_from_table(self, table):
        pass

    @abc.abstractmethod
    def get_data_from_table_in_parallel(self, table, num_partitions):
        pass

    @abc.abstractmethod
    def get_data_from_query(self, query):
        pass
