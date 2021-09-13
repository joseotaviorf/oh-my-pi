SELECT
    INT(NULLIF(contrato,'')) AS id_contract,
    INT(NULLIF(id_imovel,'')) AS id_house,
    INT(NULLIF(codigo_corrida,'')) AS id_run,
    NULLIF(email,'') AS email,
    NULLIF(chaves_antecipadas,'') AS advanced_keys,
    NULLIF(prestador_servico,'') AS service_provider,
    NULLIF(tipo_chaves,'') AS type_of_keys,
    NULLIF(fase_contrato,'') AS contract_phase,
    FLOAT(NULLIF(custo_corrida,'')) AS running_cost,
    NULLIF(status,'') AS status,
    FLOAT(NULLIF(cutsto_corrida_final,'')) AS final_running_cost,
    TO_DATE(NULLIF(dt_abertura_tarefa,''),'dd/MM/yyyy') AS dt_started_task,
    TO_DATE(NULLIF(dt_vigencia_saida,''),'dd/MM/yyyy') AS dt_max_to_send_keys,
    TO_DATE(NULLIF(dt_viagem,''),'dd/MM/yyyy') AS dt_keys_travel,
    TO_DATE(NULLIF(data,''),'dd/MM/yyyy') AS dt_ended_key_logistics
FROM
    datalake_gsheets_raw.keys_logistic_control
