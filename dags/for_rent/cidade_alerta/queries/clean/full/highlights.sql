SELECT
    GET_JSON_OBJECT(REPLACE(_id, '$', ''), '$.oid') AS id,
    field,
    rank
FROM
    datalake_cidade_alerta_raw.highlights
