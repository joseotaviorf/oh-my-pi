SELECT
    id,
    iddevedor AS id_debtor,
    idempresa AS id_company,
    id_uuid,
    fone AS phone,
    tipo AS type,
    status,
    contato AS contact,
    hot_number,
    origem AS origin,
    qualificacao AS qualification,
    whatsapp,
    data AS date,
    data_inativa AS dt_inactive
FROM
    datalake_iaf_raw.vi_319_tb_devedor_fones
