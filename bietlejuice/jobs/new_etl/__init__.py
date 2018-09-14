import os

dir_path = os.path.dirname(os.path.realpath(__file__))
DW_DIR = os.path.join(dir_path, '../../db/dw')
DW_QUERIES_DIR = os.path.join(dir_path, '../../db/dw/queries')
DATALAKE_QUERIES_DIR = os.path.join(dir_path, '../../db/datalake/queries')
LEAD_VARIANT_CONFIG_DIR = os.path.join(dir_path, 'leads/variant_config')
ODS_QUERIES_DIR = os.path.join(dir_path, '../../db/ODS/queries')
SOURCE_QUERIES_DIR = os.path.join(dir_path, '../../db/source/queries')
