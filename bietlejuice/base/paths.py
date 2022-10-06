import os

# TODO: create a constant inside db package and use here instead of the definition `../db`
DB_SQL_PATH = os.path.join(os.path.dirname(os.path.realpath(__file__)), "../db")

DATALAKE_METADATA_PATH = f"{DB_SQL_PATH}/datalake/metadata"
DATA_QUALITY_TESTS_PATH = f"{DB_SQL_PATH}/datalake/data_quality"
DATALAKE_SQL_DIR = f"{DB_SQL_PATH}/datalake"  # TODO: refactor to DATALAKE_SQL_PATH
QUERIES_DATALAKE_PATH = (
    DATALAKE_SQL_DIR + "/queries/"
)  # TODO: refactor to DATALAKE_QUERY_PATH
DDL_DATALAKE_PATH = DATALAKE_SQL_DIR + "/ddl/"  # TODO: refactor to DATALAKE_DDL_PATH

DW_QUERY_PATH = f"{DB_SQL_PATH}/dw/queries/"
