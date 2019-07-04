from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger('Consumer')


class Consumer:

    @logger
    def get_table_names_and_sizes(self):
        raise NotImplementedError()

    @logger
    def get_data_from_table(self, table_name):
        raise NotImplementedError()

    @logger
    def get_data_from_table_in_parallel(self, table_name, concurrency):
        raise NotImplementedError()

    @logger
    def get_data_from_query(self, query):
        raise NotImplementedError()

    @logger
    def get_table_schema(self, table_name):
        raise NotImplementedError()

    @logger
    def is_db_empty(self):
        try:
            result = self.get_table_names_and_sizes()
        except Exception as e:
            raise RuntimeError('m=is_db_empty, msg=Database of this consumer does not exist., e={}'.format(e))
        if result and result.count():
            return False

        return True
