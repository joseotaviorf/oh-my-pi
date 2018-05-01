from itertools import combinations

from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import logger, _logger

from base_etl import BaseETL


class BaseTest(object):
    @staticmethod
    @logger
    def test_file_query(file_path, enum_db, assertion, blocking=False, encoding='utf-8'):
        query = BaseETL.get_query_from_file_name(file_name=file_path)
        return BaseTest.__test_query(query=query, enum_db=enum_db, assertion=assertion, blocking=blocking,
                                     encoding=encoding)

    @staticmethod
    @logger
    def test_raw_query(query, enum_db, assertion, blocking=False, encoding='utf-8'):
        return BaseTest.__test_query(query=query, enum_db=enum_db, assertion=assertion, blocking=blocking,
                                     encoding=encoding)

    @staticmethod
    @logger
    def get_query_result_for_comparison(query, enum_db=None, encoding='utf-8', from_athena=False):
        if query == '':
            return None

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
    def compare_sources(acceptable_diff, sources_list):
        for x, y in combinations(filter(None, sources_list), 2):
            if abs((x / float(y)) - 1) > acceptable_diff:
                _logger.warn('m=compare_sources, msg=sources are different')
                raise Exception

    @staticmethod
    @logger
    def check_for_duplicates(schema, table, key, enum_db):
        output = BaseTest.get_query_result_for_comparison(
            query='select {0}, count(1) from {1}.{2} group by {0} having count(1)>1'.format(key, schema, table),
            enum_db=enum_db
        )

        # returns true if has more rows besides the header
        if len(output) > 1:
            _logger.error('m=__test_duplicates, msg={} has duplicates'.format(table))
            raise Exception

        _logger.info('m=__test_duplicates, msg={} is free from duplicates'.format(table))

    @staticmethod
    @logger
    def check_for_emptiness(schema, table, enum_db):
        output = BaseTest.get_query_result_for_comparison(
            query='select count(1) from {}.{}'.format(schema, table),
            enum_db=enum_db
        )

        # returns true if has more rows besides the header
        if output[1][0] == 0:
            _logger.error('m=is_empty, msg={} is empty'.format(table))
            raise Exception

        _logger.info('m=is_empty, msg={} is not empty'.format(table))

    @staticmethod
    def are_counts_equal(_dict):
        _logger.info('m=are_counts_equal, _dict={}'.format(_dict))

        comparison_list = []
        for source in _dict['sources']:
            _query = BaseETL.get_query_from_file_name(source['file_path'])
            query_result = BaseTest.get_query_result_for_comparison(
                query=_query,
                enum_db=source['enum_db'],
                from_athena=source['from_athena'] if 'from_athena' in source else False
            )

            if query_result is None:
                continue

            _return = query_result.values[0][0] if 'from_athena' in source and source['from_athena'] else \
                query_result[1][0]
            comparison_list.append(_return)

        BaseTest.compare_sources(_dict['acceptable_diff'], comparison_list)
        _logger.info('m=__test_count, msg=counts are all equal')
