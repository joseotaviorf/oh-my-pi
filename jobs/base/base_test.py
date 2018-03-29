from jobs.base.base_etl import BaseETL
from qa_python_utils.default_logger import logger, _logger


class BaseTest(object):
    @staticmethod
    @logger
    def _get_query_from_file_name(file_path):
        try:
            with open(file_path) as f:
                return f.read()
        except IOError:
            _logger.info('m=__get_query_from_file_name, file_path={}, msg=file not found'.format(file_path))
            return ''

    @staticmethod
    @logger
    def test_file_query(file_path, enum_db, assertion, blocking=False, encoding='utf-8'):
        query = BaseTest._get_query_from_file_name(file_path=file_path)
        _return = BaseETL.from_db_query(
            db_enum=enum_db,
            query=query,
            encoding=encoding
        )

        if blocking and _return != assertion:
            raise Exception

        return _return == assertion


