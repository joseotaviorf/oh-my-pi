SELECT
    id,
    condo_id AS id_condo,
    inputCondoName AS input_condo_name,
    registrantType AS type_registrant,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated
FROM
    datalake_ebdb_raw.condonameshistory