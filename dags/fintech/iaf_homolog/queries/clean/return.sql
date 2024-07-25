SELECT
    id,
    idempresa AS id_company,
    codigo AS code,
    processo AS process,
    idcredor AS id_creditor,
    iddevedor AS id_debtor,
    data_cad AS dt_cad,
    data_dev  AS dt_dev,
    obs,
    cod_motivo  AS code_reason,
    motivo  AS reason,
    status,
    usuario_conc  AS user_conc,
    usuario_incl AS user_incl,
    origem AS origin,
    last_update AS ts_updated
FROM
    datalake_iaf_raw.vi_319_tb_devolucao
