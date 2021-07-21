SELECT
    id,
    imovel_id AS id_house,
    uid,
    ip,
    CAST(criado_em AS TIMESTAMP) AS ts_created,
    CAST(deletado_em AS TIMESTAMP) AS ts_deleted
FROM
    datalake_casa_mineira_portal_raw.favorito