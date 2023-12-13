SELECT
    id,
    idempresa AS id_company,
    idacordo AS id_agreement,
    idtitulo AS id_title,
    processo AS process,
    vl_tx_contrato AS contract_tax_value,
    vl_protesto AS protest_value,
    vl_desconto AS discount_value,
    vl_juros AS fee_value,
    vl_multa AS fine_value,
    vl_honorarios AS honorary_value,
    vl_capital AS capital_value,
    vl_capital_liq AS capital_net_value,
    vl_capital_corrig AS capital_adjusted_value,
    last_update AS ts_updated
FROM
    datalake_iaf_raw.vi_319_tb_acordo_tit
