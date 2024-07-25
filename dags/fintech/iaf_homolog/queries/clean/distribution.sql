SELECT
    id,
    idempresa AS id_company,
    iddevedor AS id_debtor,
    processo AS process,
    usuario_distri AS user_distribution,
    cobrador AS charger,
    data_distri AS dt_distribution,
    last_update AS ts_updated
FROM
    datalake_iaf_raw.vi_319_tb_distribuicao
