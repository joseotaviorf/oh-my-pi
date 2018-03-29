import os

dir_path = os.path.dirname(os.path.realpath(__file__))
DW_TEST_QUERIES_DIR = os.path.join(dir_path, '../../../db/3.dw/public/queries/tests')
UNIT_ECONOMICS_TEST_QUERIES_DIR = os.path.join(dir_path, '../../../db/ODS/unit_economics/test/queries')

DEFAULT_DAG_OWNER = 'Data Team'