select
    id,
    atualizadoEm as ts_updated,
    criadoEm as ts_created,
    nomeArquivo as file_name,
    sequencia as sequence,
    tipo as type,
    url,
    proponente_id as id_proponent,
    contentType as content_type
from
    datalake_ebdb_raw.documentoproposta