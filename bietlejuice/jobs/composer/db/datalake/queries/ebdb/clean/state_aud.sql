SELECT
    id AS id_state,
    REV AS rev,
    REVTYPE AS rev_type,
    abreviacao AS abbrevation,
    nome AS name
FROM
    datalake_ebdb_raw.`estado_aud`