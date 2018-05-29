import os

dir_path = os.path.dirname(os.path.realpath(__file__))
DW_DIR = os.path.join(dir_path, '../../db/3.dw')
DATALAKE_QUERIES_DIR = os.path.join(dir_path, '../../db/2.datalake/queries')
QUERIES_DIR = os.path.join(dir_path, '../../../db/1.source/ebdb/queries')
ODS_QUERIES_DIR = os.path.join(dir_path, '../../../db/ODS/queries')
DW_QUERIES_DIR = os.path.join(dir_path, '../../../db/3.dw/public/queries')
