from base_etl import BaseETL
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
        return BaseTest.__test_query(query=query, enum_db=enum_db, assertion=assertion, blocking=blocking, encoding=encoding)

    @staticmethod
    @logger
    def test_raw_query(query, enum_db, assertion, blocking=False, encoding='utf-8'):
        return BaseTest.__test_query(query=query, enum_db=enum_db, assertion=assertion, blocking=blocking, encoding=encoding)

    @staticmethod
    @logger
    def __test_query(query, enum_db, assertion, blocking, encoding):
        _return = BaseETL.from_db_query(
            db_enum=enum_db,
            query=query,
            encoding=encoding
        )

        if _return is not None and len(_return) == 1 and assertion is None:
            return True

        if blocking and _return[1] != assertion:
            raise Exception

        return _return[1] == assertion
