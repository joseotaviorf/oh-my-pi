SELECT
    cod_hist_cli AS id_historical_customers,
    cod_tit AS id_contract,
    cod_dev AS id_debtor,
    cod_ocor AS id_occurrence,
    usuario_cad AS id_operator,
    cod_hist_cli_mat AS id_service_digital_agent,
    complemento_hist_cli AS extra_information_occurrence,
    data_cad AS ts_service,
    dt_agen_hist AS ts_scheduling,
    year,
    month,
    day,
    NOW() AS ts_load
FROM datalake_webhelp_raw.historicos_clientes
WHERE
    MAKE_DATE(year,month,day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY ROW_NUMBER() OVER(PARTITION BY cod_hist_cli ORDER BY subfolder DESC) = 1
