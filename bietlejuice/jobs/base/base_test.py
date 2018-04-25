from base_etl import BaseETL
from qa_python_utils.default_logger import logger, _logger
from qa_python_utils.aws.athena import AthenaClient
from itertools import combinations


class BaseTest(object):
    @staticmethod
    @logger
    def test_file_query(file_path, enum_db, assertion, blocking=False, encoding='utf-8'):
        query = BaseETL.get_query_from_file_name(file_name=file_path)
        return BaseTest.__test_query(query=query, enum_db=enum_db, assertion=assertion, blocking=blocking, encoding=encoding)

    @staticmethod
    @logger
    def test_raw_query(query, enum_db, assertion, blocking=False, encoding='utf-8'):
        return BaseTest.__test_query(query=query, enum_db=enum_db, assertion=assertion, blocking=blocking, encoding=encoding)

    @staticmethod
    @logger
    def get_query_result_for_comparison(query, enum_db=None, encoding='utf-8', from_athena=False):
        if from_athena:
            return AthenaClient('5a-datalake').execute_query_and_return_dataframe(query)

        return BaseETL.from_db_query(
            db_enum=enum_db,
            query=query,
            encoding=encoding
        )

    @staticmethod
    @logger
    def __test_query(query, enum_db, assertion, blocking, encoding):
        _return = BaseTest.get_query_result_for_comparison(query, enum_db, encoding)
        if _return is not None and len(_return) == 1 and assertion is None:
            return True

        if blocking and _return[1] != assertion:
            raise Exception

        return _return[1] == assertion

    @staticmethod
    @logger
    def compare_sources(unacceptable_diff, *sources):
        for x, y in combinations(filter(None, sources), 2):
            if abs((x / float(y)) - 1) >= unacceptable_diff:
                _logger.warn('m=compare_sources, msg=sources are different')
                raise Exception
