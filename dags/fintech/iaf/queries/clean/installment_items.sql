SELECT
    id,
    idempresa AS id_company,
    idprestacao AS id_installment,
    idbaixa AS id_write_off,
    nprestacao AS number_installment,
    obs,
    last_update AS ts_updated
FROM
    datalake_iaf_raw.vi_319_tb_prestacao_itens
