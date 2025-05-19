select
    a.id,
    a.name,
    a.criadoem as ts_created,
    a.atualizadoem as ts_updated
from datalake_ebdb_raw.AccessAuthorizationType a
