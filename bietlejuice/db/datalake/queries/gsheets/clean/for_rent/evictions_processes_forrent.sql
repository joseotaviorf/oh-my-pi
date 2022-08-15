SELECT
    contract_id AS id_contract,
    process_number AS id_process,
    alert_str AS alert_message,
    resp AS responsible,
    process_status,
    action_type as action_type_name,
    CASE 
        WHEN is_cav = "Sim" THEN TRUE
        WHEN is_cav = "Não" THEN FALSE
    END AS is_cav,
    CASE 
        WHEN is_fraud = "Sim" THEN TRUE
        WHEN is_fraud = "Não" THEN FALSE
    END AS is_fraud,
    TO_DATE(insertion_date, 'dd/MM/yyyy') as dt_insertion,
    TO_DATE(sentence_date, 'dd/MM/yyyy') as dt_sentence,
    TO_DATE(final_sentence_date, 'dd/MM/yyyy') as dt_final_sentence
FROM
    datalake_gsheets_raw.evictions_processes_forrent