import os

dir_path = os.path.dirname(os.path.realpath(__file__))
DW_DIR = os.path.join(dir_path, '../../db/3.dw')
DATALAKE_QUERIES_DIR = os.path.join(dir_path, '../../db/2.datalake/queries')
SORTINGHAT_QUERIES_DIR = os.path.join(dir_path, '../../db/sorting_hat/queries')
EBDB_QUERIES_DIR = os.path.join(dir_path, '../../db/1.source/ebdb/queries')
LEAD_VARIANT_CONFIG_DIR = os.path.join(dir_path, 'leads/variant_config')
