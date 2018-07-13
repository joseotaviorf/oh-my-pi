import os

dir_path = os.path.dirname(os.path.realpath(__file__))
DW_TEST_QUERIES_DIR = os.path.join(dir_path, '../../db/3.dw/public/queries/tests')
ODS_TEST_QUERIES_DIR = os.path.join(dir_path, '../../db/ODS/queries/tests')
DATALAKE_TEST_QUERIES_DIR = os.path.join(dir_path, '../../db/2.datalake/queries/tests')
DATALAKE_QUERIES_DIR = os.path.join(dir_path, '../../db/2.datalake/queries')
ODS_STAGING_TEST_QUERIES_DIR = os.path.join(dir_path, '../../db/ODS/staging/queries/tests')
EBDB_TEST_QUERIES_DIR = os.path.join(dir_path, '../../db/1.source/ebdb/queries/tests')
DW_STAGING_QUERIES_DIR = os.path.join(dir_path, '../../db/3.dw/staging/queries')
QUERIES_EBDB_SUPPLY_DEMAND_DIR = os.path.join(dir_path, '../../db/1.source/ebdb/queries/supply_demand_funnel')

DEFAULT_DAG_OWNER = 'Data Team'
