SELECT
    contract_id AS id_contract,
    process_number AS id_process,
    alert_str AS alert_message,
    resp AS responsible,
    process_status,
    action_type as action_type_name,
    deal_status,
    contract_status,
    off_status,
    CASE 
        WHEN is_cav = "Sim" THEN TRUE
        WHEN is_cav = "Não" THEN FALSE
    END AS is_cav,
    CASE 
        WHEN is_fraud = "Sim" THEN TRUE
        WHEN is_fraud = "Não" THEN FALSE
    END AS is_fraud,
    CASE 
        WHEN abandonment_bool = "Sim" THEN TRUE
        WHEN abandonment_bool = "Não" THEN FALSE
    END AS is_abandonment,
    TO_DATE(insertion_date, 'dd/MM/yyyy') as dt_insertion,
    TO_DATE(sentence_date, 'dd/MM/yyyy') as dt_sentence,
    TO_DATE(final_sentence_date, 'dd/MM/yyyy') as dt_final_sentence,
    TO_DATE(distribution_date, 'dd/MM/yyyy') as dt_distribution,
    TO_DATE(deal_begin_date, 'dd/MM/yyyy') as dt_deal_begin,
    TO_DATE(deal_end_date, 'dd/MM/yyyy') as dt_deal_end,
    TO_DATE(deal_paid_dt, 'dd/MM/yyyy') as dt_deal_paid,
    TO_DATE(no_deal_paid_dt, 'dd/MM/yyyy') as dt_no_deal_paid,
    TO_DATE(finalizing_dt, 'dd/MM/yyyy') as dt_finalizing,
    TO_DATE(termination_dt, 'dd/MM/yyyy') as dt_contract_termination
FROM
    datalake_gsheets_raw.evictions_processes_forrent