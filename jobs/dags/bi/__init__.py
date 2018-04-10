import os

dir_path = os.path.dirname(os.path.realpath(__file__))
DW_TEST_QUERIES_DIR = os.path.join(dir_path, '../../../db/3.dw/public/queries/tests')
ODS_TEST_QUERIES_DIR = os.path.join(dir_path, '../../../db/ODS/public/queries/tests')
DATALAKE_RAW_TEST_QUERIES_DIR = os.path.join(dir_path, '../../../db/2.datalake/raw/queries/tests')

DEFAULT_DAG_OWNER = 'Data Team'
