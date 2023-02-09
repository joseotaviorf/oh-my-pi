SELECT 
    CAST(id AS BIGINT) AS id_conservation_status_item,
    CAST(itemId AS BIGINT) AS id_item,
    conservation,
    CAST(criadoEm AS TIMESTAMP) AS ts_created,
    CAST(atualizadoEm AS TIMESTAMP) AS ts_updated
FROM
    datalake_ebdb_raw.conservationitemstatus