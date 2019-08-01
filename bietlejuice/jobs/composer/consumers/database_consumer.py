from abc import ABC, abstractmethod

from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("DatabaseConsumer")


class DatabaseConsumer(ABC):
    @abstractmethod
    def get_table_names_and_sizes(self, table_name_match=None):
        pass

    @abstractmethod
    def get_data_from_table(self, table_name):
        pass

    @abstractmethod
    def get_data_from_table_in_parallel(self, table_name, concurrency):
        pass

    @abstractmethod
    def get_data_from_query(self, query):
        pass

    @abstractmethod
    def get_table_schema(self, table_name):
        pass

    @logger
    def is_db_empty(self):
        try:
            result = self.get_table_names_and_sizes()
        except Exception as e:
            raise RuntimeError(
                "m=is_db_empty, msg=Database of this consumer does not exist., e={}".format(
                    e
                )
            )
        if result and result.count():
            return False

        return True
