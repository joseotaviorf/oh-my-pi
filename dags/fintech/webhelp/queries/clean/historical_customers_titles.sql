SELECT
    cod_hist_cli AS id_historical_customers,
    cod_tit AS id_contract,
    NOW() AS ts_load
FROM datalake_webhelp_raw.historicos_clientes_titulos
