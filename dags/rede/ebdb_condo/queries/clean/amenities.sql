SELECT
    id,
    codigo as code,
    nome as name,
    editavel as is_editable,
    slug as slug,
    atualizadoem as ts_updated,
    ativo as is_active,
    criadoem as ts_created
FROM
    datalake_ebdb_raw.amenidades