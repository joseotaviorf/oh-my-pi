SELECT
    id,
    imovel_id AS id_house,
    tipo_id AS id_type,
    arquivo AS file,
    criado_por AS created_by,
    removido_por AS removed_by,
    CAST(criado_em AS TIMESTAMP) AS ts_created,
    CAST(deletado_em AS TIMESTAMP) AS ts_deleted
FROM
    datalake_casa_mineira_crm_raw.documento