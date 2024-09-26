SELECT
    cod_fup AS id_action,
    contrato AS id_contract,
    login_operador AS id_operator,
    desc_fup AS description,
    fluxo AS contract_flow,
    status_indicador AS contract_status,
    fx_atraso AS delay_range,
    alo,
    cpc,
    acordo AS agreement,
    canal AS channel,
    telefone AS phone,
    saldo_devedor AS due_amount,
    saldo_recuperado AS recovered_amount,
    tempo_falado AS call_duration,
    hora_registro AS action_hour,
    TO_DATE(data_registro, 'dd/MM/yyyy HH:mm:ss') AS dt_action,
    data_admissao AS dt_operator_admission,
    ts_load,
    year,
    month,
    day
FROM datalake_paschoalotto_raw.tb_arquivo_ret
WHERE
    MAKE_DATE(year,month,day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
