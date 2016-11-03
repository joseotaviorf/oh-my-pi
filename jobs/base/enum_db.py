from enum import Enum


class EnumDb(Enum):
    QuintoAndar_ebdb = 'ENV_EBDB'
    BI_Staging = 'ENV_BI_STG'
    BI_ODS = 'ENV_BI_ODS'
    BI_DW = 'ENV_BI_DW'
    LOCAL_ODS = 'ENV_LOCAL_BI_ODS'
    LOCAL_DW = 'ENV_LOCAL_BI_DW'

class EnumDbType(Enum):
    PostgreSQL = 'postgres'
    MySQL = 'mysql'
    Redshift = 'redshift'