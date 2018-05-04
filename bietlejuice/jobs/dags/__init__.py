import os

dir_path = os.path.dirname(os.path.realpath(__file__))
DW_TEST_QUERIES_DIR = os.path.join(dir_path, '../../db/3.dw/public/queries/tests')
ODS_TEST_QUERIES_DIR = os.path.join(dir_path, '../../db/ODS/public/queries/tests')
DATALAKE_RAW_TEST_QUERIES_DIR = os.path.join(dir_path, '../../db/2.datalake/raw/queries/tests')
ODS_STAGING_TEST_QUERIES_DIR = os.path.join(dir_path, '../../db/ODS/staging/queries/tests')
EBDB_TEST_QUERIES_DIR = os.path.join(dir_path, '../../db/1.source/ebdb/queries/tests')

DEFAULT_DAG_OWNER = 'Data Team'
