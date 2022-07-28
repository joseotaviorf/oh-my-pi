SELECT
    atributo_id AS id_attribute,
    imovel_id AS id_house,
    CAST(criado_em AS TIMESTAMP) AS ts_created,
    CAST(deletado_em AS TIMESTAMP) AS ts_deleted
FROM
    datalake_casa_mineira_portal_raw.imovel_atributo