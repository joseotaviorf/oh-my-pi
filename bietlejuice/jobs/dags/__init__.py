import os

dir_path = os.path.dirname(os.path.realpath(__file__))
DW_QUERIES_DIR = os.path.join(dir_path, '../../db/dw/public/queries/tests')
DW_TEST_QUERIES_DIR = os.path.join(dir_path, '../../db/dw/public/queries/tests')
ODS_TEST_QUERIES_DIR = os.path.join(dir_path, '../../db/ODS/queries/tests')
DATALAKE_TEST_QUERIES_DIR = os.path.join(dir_path, '../../db/datalake/queries/tests')
DATALAKE_QUERIES_DIR = os.path.join(dir_path, '../../db/datalake/queries')
SOURCE_QUERIES_TESTS_DIR = os.path.join(dir_path, '../../db/source/queries/tests')
SOURCE_QUERIES_DIR = os.path.join(dir_path, '../../db/source/queries/')

DEFAULT_DAG_OWNER = 'Data Team'
